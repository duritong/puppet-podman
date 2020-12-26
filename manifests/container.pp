# manages a running container
define podman::container (
  String[1,32]
    $user,
  Pattern[/^[\S]*$/]
    $image,
  Variant[String[1],Integer]
    $uid,
  Variant[String[1],Integer]
    $gid,
  Optional[String[1]]
    $group            = undef,
  Enum['present','absent']
    $ensure           = 'present',
  Enum['pod','container']
    $deployment_mode  = 'container',
  String
    $container_name   = $name,
  Optional[String]
    $command          = undef,
  Optional[String]
    $pod_file         = undef,
  Array[Pattern[/\A(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])){3}:)?\d+:\d+(\/(tcp|udp))?\z/]]
    $publish          = [],
  Hash[Integer[1,65535], Hash]
    $publish_socket   = {},
  Array[Pattern[/^[a-zA-Z0-9_]+=.+$/]]
    $envs             = [],
  Array[Variant[Integer,Pattern[/^\d+(\/(tcp|udp))?$/]]]
    $publish_firewall = [],
  Variant[Hash[Variant[Stdlib::Unixpath, String[1]],
    Stdlib::Unixpath],Array[Pattern[/^\/.*:\/[^:]*(:(ro|rw|Z)(,Z)?)?/]]]
    $volumes          = {},
  Hash
    $run_flags        = {},
  Optional[Stdlib::Unixpath]
    $homedir          = undef,
  Boolean
    $manageuserhome   = true,
  Boolean
    $manage_user      = true,
  Boolean
    $use_rsyslog      = true,
  Hash[Pattern[/^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])(:\d+)?$/],Struct[{ user => Pattern[/^[a-zA-Z0-9_\.]+$/], password => Pattern[/^[a-zA-Z0-9\|\+\.\*\%\_]+$/], }]]
    $auth             = {},
  Hash[Variant[Stdlib::Unixpath, String[1]], Struct[{ content => Optional[String], source => Optional[String], ensure => Optional[Enum['directory','file']], replace => Optional[Boolean], owner => Optional[Variant[String,Integer]], mode => Optional[Stdlib::Filemode] }]]
    $user_files       = {},
  Stdlib::Unixpath
    $logpath          = '/var/log/containers',
  Hash
    $configuration    = {},
) {
  if $homedir {
    $real_homedir = $homedir
  } else {
    $real_homedir = "/home/${user}"
  }
  if $gid == 'uid' {
    $real_gid = $uid
  } else {
    $real_gid = $gid
  }
  if $group {
    $real_group = $group
  } else {
    $real_group = $user
  }
  include podman
  $sanitised_con_name = regsubst($container_name, '[^0-9A-Za-z._]', '-', 'G')
  $unique_name = regsubst("con-${user}-${container_name}", '[^0-9A-Za-z._]', '-', 'G')

  $_real_volumes = $volumes ? {
    Array   => Hash($volumes.map |$s| {
      $v = split($s,':')
      if $v[2] {
        [$v[0], join([$v[1],$v[2]],':')]
      } else {
        [$v[0], $v[1]]
      }
    }),
    default => $volumes,
  }
  $real_volumes = Hash($_real_volumes.map |$k,$v| {
    if $k =~ Stdlib::Unixpath or $k =~ /^tmpfs/ {
      $_k = $k
    } else {
      $_k = "${real_homedir}/${k}"
    }
    [$_k, $v]
  })

  if $use_rsyslog {
    rsyslog::confd {
      $unique_name:
        ensure  => $ensure,
        content => template('podman/rsyslog-confd.erb'),
    } -> logrotate::rule {
      $unique_name:
        ensure       => $ensure,
        path         => "${logpath}/${unique_name}.log",
        compress     => true,
        copytruncate => true,
        dateext      => true,
        create       => true,
        create_mode  => '0640',
        create_owner => 'root',
        create_group => $real_group,
        su           => true,
        su_user      => 'root',
        su_group     => $real_group,
    } -> file {
      # manage file to workaround
      # https://access.redhat.com/solutions/3967061
      "${logpath}/${unique_name}.log":
        ensure => file,
        mode   => '0640',
        owner  => 'root',
        group  => $real_group,
    }
  }
  if !defined(Podman::Container::User[$user]) {
    podman::container::user {
      $user:
        ensure      => $ensure,
        manage_user => $manage_user,
        group       => $real_group,
        uid         => $uid,
        gid         => $real_gid,
        homedir     => $real_homedir,
        managehome  => $manageuserhome,
    }
  }
  if ($ensure == 'present') and !empty($envs) {
    $_envs = $envs.map |$e| {
      if $e =~ /^([a-zA-Z0-9_]+)=%%TROCLA%%$/ {
        "${1}=\"${trocla("container_${name}_${1}",'plain')}\""
      } else {
        $e
      }
    }
  } else {
    $_envs = []
  }

  if $deployment_mode == 'pod' {
    if $pod_file {
      $pod_yaml_path = "/var/lib/containers/users/${user}/data/pod-${sanitised_con_name}.yaml"
      file {
        $pod_yaml_path:
          owner  => 'root',
          group  => $real_gid,
          mode   => '0640',
          notify => Systemd::Unit_file["${unique_name}.service"],
          before => Podman::Pod_images[$name];
      }
      if $pod_file =~ /puppet:\/\// {
        File[$pod_yaml_path] {
          source => $pod_file,
        }
      } else {
        File[$pod_yaml_path] {
          content => template($pod_file),
        }
      }
    }

    $systemd_unit_file = 'podman/user-pod.service.erb'
  } else {
    file {
      "/var/lib/containers/users/${user}/bin/${unique_name}.sh":
        ensure  => $ensure,
        owner   => 'root',
        group   => $real_gid,
        mode    => '0750',
        seltype => 'container_runtime_exec_t',
        notify  => Systemd::Unit_file["${unique_name}.service"],
        require => Podman::Container::User[$user];
    }
    $systemd_unit_file = 'podman/user-container.service.erb'
  }

  systemd::unit_file {
    "${unique_name}.service":
      ensure => $ensure,
  }
  if $ensure != 'absent' {
    Systemd::Unit_file["${unique_name}.service"] {
      content => template($systemd_unit_file),
      enable  => true,
      active  => true,
      require => Package['podman'],
    }
  } else {
    Systemd::Unit_file["${unique_name}.service"] {
      enable => false,
      active => false,
    }
  }

  if $ensure == 'present' {
    if $run_flags['security-opt-label-type'] {
      require "podman::selinux::policy::${run_flags['security-opt-label-type']}"
      Class["podman::selinux::policy::${run_flags['security-opt-label-type']}"] ~> Systemd::Unit_file["${unique_name}.service"]
    }

    if $run_flags['security-opt-seccomp'] {
      $seccomp_file = "/var/lib/containers/users/${user}/data/seccomp-${sanitised_con_name}.json"
      if $run_flags['security-opt-seccomp'] =~ Pattern[/(?i:^puppet:\/\/)/] {
        $seccomp_src = $run_flags['security-opt-seccomp']
      } elsif $run_flags['security-opt-seccomp'] =~String {
        $seccomp_src = "puppet:///modules/site_podman/seccomp/${run_flags['security-opt-seccomp']}.json"
      } else {
        $seccomp_src = [
          "puppet:///modules/site_podman/seccomp/${name}.json",
          "puppet:///modules/site_podman/seccomp/${container_name}.json",
        ]
      }
      file {
        $seccomp_file:
          source => $seccomp_src,
          owner  => 'root',
          group  => $real_gid,
          mode   => '0750',
          notify => Systemd::Unit_file["${unique_name}.service"],
      }
    }

    if empty($publish_socket) and $deployment_mode == 'container' {
      if $run_flags['network'] == 'isolated' {
        fail('isolated network is not supported without a publish_socket')
      }
      File["/var/lib/containers/users/${user}/bin/${unique_name}.sh"] {
        content => template('podman/user-container.sh.erb'),
      }
    } elsif $deployment_mode == 'container' {
      $publish_socket.each |$k,$v| {
        if $v['security-opt-label-type'] {
          require "podman::selinux::policy::${v['security-opt-label-type']}"
          Class["podman::selinux::policy::${v['security-opt-label-type']}"] ~> Systemd::Unit_file["${unique_name}.service"]
        }
      }
      File["/var/lib/containers/users/${user}/bin/${unique_name}.sh"] {
        content => template('podman/user-pod.sh.erb'),
      }
    }
    if $deployment_mode == 'container' {
      podman::image {
        $name:
          user    => $user,
          group   => $real_group,
          image   => $image,
          uid     => $uid,
          homedir => $real_homedir,
      } -> Systemd::Unit_file["${unique_name}.service"]
    } else {
      podman::pod_images {
        $name:
          user     => $user,
          group    => $real_group,
          pod_yaml => $pod_yaml_path,
          uid      => $uid,
          homedir  => $real_homedir,
      } -> Systemd::Unit_file["${unique_name}.service"]
    }
    if $deployment_mode == 'pod' or (!empty($publish_socket) and !defined(Podman::Image["${user}-pause"])) {
      # make sure we have also the pause image fetched
      if !defined(Podman::Image["${user}-pause"]) {
        podman::image {
          "${user}-pause":
            user    => $user,
            group   => $real_group,
            image   => 'k8s.gcr.io/pause:3.1',
            uid     => $uid,
            homedir => $real_homedir,
        } -> Systemd::Unit_file["${unique_name}.service"]
      }
    }

    if !empty($publish_socket) and !defined(Podman::Image["${user}-socat"]) {
      podman::image {
        "${user}-socat":
          user    => $user,
          group   => $real_group,
          image   => 'registry.code.immerda.ch/immerda/container-images/socat:7',
          uid     => $uid,
          homedir => $real_homedir,
      } -> Systemd::Unit_file["${unique_name}.service"]
    }

    $publish_firewall.each |$pport| {
      $port_arr = split(String($pport),/\//)
      $proto = pick($port_arr[1],'tcp')
      if $publish.any |$p| { $p =~ Regexp("^${port_arr[0]}:([0-9]+)?(/${proto})?$") } {
        shorewall::rule {
          "${unique_name}-${pport}":
            destination     => '$FW',
            source          => 'net',
            order           => 240,
            proto           => $proto,
            destinationport => $port_arr[0],
            action          => 'ACCEPT',
            require         => Systemd::Unit_file["${unique_name}.service"],
        }
      }
    }
    $user_files_defaults = {
      owner  => $uid,
      group  => $real_group,
      mode   => '0640',
      notify => Systemd::Unit_file["${unique_name}.service"],
    }
    $user_files.each |$k,$v| {
      if $k =~ Stdlib::Unixpath {
        $_k = $k
      } else {
        $_k = "${real_homedir}/${k}"
      }
      if 'content' in $v and $v['content'] =~ /%%TROCLA_/ {
        $trocla_data = $v['content']
        $_v = $v.merge( { content => Sensitive(trocla::gsub($v['content'], { prefix => "container_${name}_", })) })
      } else {
        $_v = $v
      }
      file {
        $_k:
          * => $user_files_defaults.merge($_v),
      }
    }
    file {
      "/var/lib/containers/users/${user}/data/auth-${name}.yaml":
        content => template('podman/auth-file.yaml.erb'),
        owner   => 'root',
        group   => $real_group,
        mode    => '0440',
    } -> concat::fragment { "podman-auth-files-${user}-${name}":
      target  => "podman-auth-files-${user}", # no newline!
      content => "/var/lib/containers/users/${user}/data/auth-${name}.yaml ",
    }
    concat::fragment {
      "${name}-image-lifecycle":
        target  => "/etc/cron.daily/podman-${user}-image-lifecycle.sh",
        content => template('podman/user-image-lifecycle.erb');
    }
  }
}
