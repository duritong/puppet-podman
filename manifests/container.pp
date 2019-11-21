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
    $group          = undef,
  Enum['present','absent']
    $ensure         = 'present',
  String
    $container_name = $name,
  Optional[String]
    $command        = undef,
  Array[Pattern[/^\d+:\d+$/]]
    $publish        = [],
  Array[Variant[Integer,Pattern[/^\d+(:(tcp|udp))?$/]]]
                           $publish_firewall = [],
  Hash[Stdlib::Compat::Absolute_Path,
    Stdlib::Compat::Absolute_Path]
                           $volumes     = {},
  Hash                     $run_flags   = {},
  Optional[Stdlib::Compat::Absolute_Path]
                           $homedir     = undef,
  Boolean                  $manage_user = true,
  Stdlib::Compat::Absolute_Path
                           $logpath     = '/var/log/containers',
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

  if $run_flags['security-opt-label-type'] {
    require "podman::selinux::policy::${run_flags['security-opt-label-type']}"
    Class["podman::selinux::policy::${run_flags['security-opt-label-type']}"] ~> Systemd::Unit_file["${unique_name}.service"]
  }

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
        before      => File["/var/lib/containers/users/${user}/bin/${unique_name}.sh"],
    }
  }
  file{
    "/var/lib/containers/users/${user}/bin/${unique_name}.sh":
      ensure  => $ensure,
      content => template('podman/user-container.sh.erb'),
      owner   => $uid,
      group   => $real_gid,
      mode    => '0750';
  } ~> systemd::unit_file{
    "${unique_name}.service":
      ensure  => $ensure,
      content => template('podman/user-container.service.erb'),
      enable  => true,
      active  => true,
      require => Package['podman'],
  }

  if $ensure == 'present' {
    podman::image{
      $name:
        user    => $user,
        group   => $real_group,
        image   => $image,
        uid     => $uid,
        homedir => $real_homedir,
    } -> Systemd::Unit_file["${unique_name}.service"]

    $publish_firewall.each |$pport| {
      $port_arr = split(String($pport),/:/)
      $proto = pick($port_arr[1],'tcp')
      if $publish.any |$p| { $p =~ Regexp("^${port_arr[0]}:") } {
        shorewall::rule {
          "${unique_name}-${pport}":
            destination     => '$FW',
            source          => 'net',
            order           => 240,
            proto           => $proto,
            destinationport => $pport,
            action          => 'ACCEPT',
            require         => Systemd::Unit_file["${unique_name}.service"],
        }
      }
    }
  }
}
