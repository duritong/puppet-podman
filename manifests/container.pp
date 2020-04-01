# manages a running container
define podman::container(
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
  Variant[Hash[Stdlib::Compat::Absolute_Path,
    Stdlib::Compat::Absolute_Path],Array[Pattern[/^\/.*:\/[^:]*(:(ro|rw|Z)(,Z)?)?/]]]
    $volumes          = {},
  Hash
    $run_flags        = {},
  Optional[Stdlib::Compat::Absolute_Path]
    $homedir          = undef,
  Boolean
    $manageuserhome   = true,
  Boolean
    $manage_user      = true,
  Boolean
    $use_rsyslog      = true,
  Stdlib::Compat::Absolute_Path
    $logpath          = '/var/log/containers',
  Hash
    $configuration    = {},
){
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
  include ::podman
  $sanitised_con_name = regsubst($container_name, '[^0-9A-Za-z._]', '-', 'G')
  $unique_name = regsubst("con-${user}-${container_name}", '[^0-9A-Za-z._]', '-', 'G')

  $real_volumes = $volumes ? {
    Array   => $volumes.map |$s| { split($s,':') },
    default => $volumes,
  }

  if $use_rsyslog {
    rsyslog::confd{
      $unique_name:
        ensure  => $ensure,
        content => template('podman/rsyslog-confd.erb'),
    } -> logrotate::rule{
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
    }
  }
  if !defined(Podman::Container::User[$user]) {
    podman::container::user{
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

  if $deployment_mode == 'pod' {
    if $pod_file {
      $pod_yaml_path = "/var/lib/containers/users/${user}/${sanitised_con_name}.yaml"
      file{
        $pod_yaml_path:
          owner  => 'root',
          group  => $real_gid,
          mode   => '0640',
          notify => Systemd::Unit_file["${unique_name}.service"];
      }
      if $pod_file =~ /puppet:\/\// {
        File[$pod_yaml_path]{
          source => $pod_file,
        }
      } else {
        File[$pod_yaml_path]{
          content => template($pod_file),
        }
      }
    }

    $systemd_unit_file = 'podman/user-pod.service.erb'
  } else {
    file{
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
  systemd::unit_file{
      "${unique_name}.service":
        ensure  => $ensure,
        content => template($systemd_unit_file),
        enable  => true,
        active  => true,
        require => Package['podman'],
  }

  if $ensure == 'present' {
    if $run_flags['security-opt-label-type'] {
      require "podman::selinux::policy::${run_flags['security-opt-label-type']}"
      Class["podman::selinux::policy::${run_flags['security-opt-label-type']}"] ~> Systemd::Unit_file["${unique_name}.service"]
    }

    if empty($publish_socket) and $deployment_mode == 'container' {
      File["/var/lib/containers/users/${user}/bin/${unique_name}.sh"]{
        content => template('podman/user-container.sh.erb'),
      }
    } elsif $deployment_mode == 'container' {
      $publish_socket.each |$k,$v| {
        if $v['security-opt-label-type']{
          require "podman::selinux::policy::${v['security-opt-label-type']}"
          Class["podman::selinux::policy::${v['security-opt-label-type']}"] ~> Systemd::Unit_file["${unique_name}.service"]
        }
      }
      File["/var/lib/containers/users/${user}/bin/${unique_name}.sh"]{
        content => template('podman/user-pod.sh.erb'),
      }
    }
    if $deployment_mode == 'container' {
      podman::image{
        $name:
          user    => $user,
          group   => $real_group,
          image   => $image,
          uid     => $uid,
          homedir => $real_homedir,
      } -> Systemd::Unit_file["${unique_name}.service"]
      if !empty($publish_socket) and !defined(Podman::Image["${user}-pause"]) {
        podman::image{
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
      podman::image{
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
  }
}
