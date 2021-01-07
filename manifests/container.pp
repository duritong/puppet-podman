# manages a running container
define podman::container (
  String[1,32] $user,
  Variant[String[1],Integer] $uid,
  Variant[String[1],Integer] $gid,
  Optional[Pattern[/^[\S]*$/]] $image = undef,
  Optional[String[1]] $group = undef,
  Enum['present','absent'] $ensure = 'present',
  Enum['userpod','pod','container'] $deployment_mode = 'container',
  String $container_name = $name,
  Optional[String] $command = undef,
  Optional[String] $pod_file = undef,
  Boolean $replace_pod_file = true,
  Podman::Publish $publish = [],
  Hash[Stdlib::Port, Hash] $publish_socket = {},
  Array[Pattern[/^[a-zA-Z0-9_]+=.+$/]] $envs = [],
  Array[Variant[Stdlib::Port,Pattern[/^\d+(\/(tcp|udp))?$/]]] $publish_firewall = [],
  Podman::Volumes $volumes = {},
  Hash $run_flags = {},
  Optional[Stdlib::Unixpath] $homedir = undef,
  Boolean $manageuserhome = true,
  Boolean $manage_user = true,
  Boolean $use_rsyslog = true,
  Podman::Auth $auth = {},
  Podman::Userfiles $user_files = {},
  Podman::Cronjobs $cron_jobs = {},
  Stdlib::Unixpath $logpath = '/var/log/containers',
  Hash $configuration = {},
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

  if $deployment_mode in ['userpod', 'pod'] {
    if !$pod_file {
      fail('Requires parameter pod_file if deploying as userpod or pod')
    }
    if 'config_directory' in $configuration {
      $pod_yaml_dir = $configuration['config_directory']
    } else {
      $pod_yaml_dir = "/var/lib/containers/users/${user}"
    }
    $pod_yaml_path = "${pod_yaml_dir}/pod-${sanitised_con_name}.yaml"

    file {
      $pod_yaml_path:
        ensure  => $ensure;
    }
    if $deployment_mode == 'userpod' {
      $system_pod_yaml_path = "${pod_yaml_dir}/system-${sanitised_con_name}.yaml"
      file {
        $system_pod_yaml_path:
          ensure  => $ensure;
      }
    }
    if $ensure == 'present' {
      if $pod_file =~ /puppet:\/\// {
        $pod_file_content = file($pod_file)
      } elsif "\n" in $pod_file {
        # if it's a multiline file, we
        # assume, it's already the whole file
        # otherwise a path to a template
        $pod_file_content = $pod_file
      } else {
        $pod_file_content = template($pod_file)
      }
      File[$pod_yaml_path] {
        content => Sensitive(trocla::gsub($pod_file_content, { prefix => "container_${name}_", })),
        replace => $replace_pod_file,
        group   => $real_gid,
        mode    => '0640',
        notify  => Systemd::Unit_file["${unique_name}.service"],
        before  => Podman::Pod_images[$name],
      }
      if $deployment_mode == 'userpod' {
        File[$pod_yaml_path] {
          owner => $user,
        }
        $system_pod_config = {
          volume_base_dir   => $real_homedir,
          container_env_dir => $pod_yaml_dir,
          logging           => { 'log-driver' => 'journald', 'log-opt' => { 'tag' => $unique_name } },
        } + pick($configuration['system_pod_config'],{}) + {
          socket_ports  => $publish_socket,
          exposed_ports => $publish_firewall,
          pidfile       => "/run/pods/${uid}/${unique_name}.pid",
          name          => $sanitised_con_name,
          selinux_label => $run_flags['security-opt-label-type'],
        }
        File[$system_pod_yaml_path] {
          content => epp('podman/userpod-system.yaml.epp', $system_pod_config),
          owner   => 'root',
          group   => $real_gid,
          mode    => '0640',
          notify  => Systemd::Unit_file["${unique_name}.service"],
        }
      } else {
        File[$pod_yaml_path] {
          owner => 'root',
        }
      }
    }

    if $deployment_mode == 'userpod' {
      $systemd_unit_file = 'podman/managed-user-pod.service.erb'
    } else {
      $systemd_unit_file = 'podman/user-pod.service.erb'
    }
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

  # actual content parsing comes more below
  $cron_jobs.each |$cron_name,$cron_vals| {
    if $ensure == 'absent' {
      $_ensure = 'absent'
    } else {
      $_ensure = pick($cron_vals['ensure'],$ensure)
    }
    systemd::timer {
      "${unique_name}-${cron_name}.timer":
        ensure => $_ensure,
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
      if !$image {
        fail('Parameter $image is required for container_deployment mode!')
      }
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
    if $deployment_mode == 'pod' or !empty($publish_socket) {
      if !empty($publish_socket) {
        $pod_name = "pod-${sanitised_con_name}"
      } else {
        $pod_name = $sanitised_con_name
      }

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
    } else {
      $pod_name = undef
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
      owner                   => $uid,
      group                   => $real_group,
      mode                    => '0640',
      selinux_ignore_defaults => true,
      notify                  => Systemd::Unit_file["${unique_name}.service"],
    }
    $user_files.each |$k,$v| {
      if $k =~ Stdlib::Unixpath {
        $_k = $k
      } else {
        $_k = "${real_homedir}/${k}"
      }
      if 'content' in $v and $v['content'] =~ /%%TROCLA_/ {
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
        notify  => Exec["init-podman-auth-file-${user}"];
    } -> concat::fragment { "podman-auth-files-${user}-${name}":
      target  => "podman-auth-files-${user}", # no newline!
      content => "/var/lib/containers/users/${user}/data/auth-${name}.yaml ",
    }
    concat::fragment {
      "${name}-image-lifecycle":
        target  => "/etc/cron.daily/podman-${user}-image-lifecycle.sh",
        content => template('podman/user-image-lifecycle.erb');
    }
    if !empty($cron_jobs) {
      require systemd::mail_on_failure
    }
    $cron_jobs.each |$cron_name,$cron_vals| {
      $timer_params = $podman::cron_timer_defaults.merge($cron_vals.filter |$i| { $i[0] in ['on_calendar', 'randomize_delay_sec'] })
      $service_params = {
        cron_name       => $cron_name,
        container_name  => $sanitised_con_name,
        service_name    => $unique_name,
        uid             => $uid,
        user            => $user,
        group           => $real_group,
        homedir         => $real_homedir,
        pod_name        => $pod_name,
        trigger_restart => false,
      }.merge($cron_vals.filter |$i| { $i[0] in ['cmd','trigger_restart'] })
      Systemd::Timer["${unique_name}-${cron_name}.timer"] {
        timer_content   => epp('podman/cron/cron.timer.epp', $timer_params),
        service_content => epp('podman/cron/cron.service.epp', $service_params),
        active          => true,
        enable          => true,
      }
    }
  }
}
