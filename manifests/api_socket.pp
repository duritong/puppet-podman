# manages a running container
define podman::api_socket (
  Variant[String[1],Integer] $uid,
  Variant[String[1],Integer] $gid,
  Optional[String[1]] $group = undef,
  Enum['present','absent'] $ensure = 'present',
  Boolean $activate_service = true,
  Optional[Stdlib::Unixpath] $homedir = undef,
  Boolean $manageuserhome = true,
  Boolean $manage_user = true,
) {
  if empty($name) {
    $name = $name
  }
  if $homedir {
    $real_homedir = $homedir
  } else {
    $real_homedir = "/home/${name}"
  }
  if $gid == 'uid' {
    $real_gid = $uid
  } else {
    $real_gid = $gid
  }
  if $group {
    $real_group = $group
  } else {
    $real_group = $name
  }
  include podman
  $unique_name = regsubst("api-${name}", '[^0-9A-Za-z._]', '-', 'G')

  if !defined(Podman::Container::User[$name]) {
    podman::container::user {
      $name:
        ensure      => $ensure,
        manage_user => $manage_user,
        group       => $real_group,
        uid         => $uid,
        gid         => $real_gid,
        homedir     => $real_homedir,
        managehome  => $manageuserhome,
    }
  }

  systemd::unit_file {
    "${unique_name}.service":
      ensure => $ensure,
  }
  if $ensure != 'absent' {
    Systemd::Unit_file["${unique_name}.service"] {
      content => template('podman/user-api-socket.service.erb'),
      enable  => $activate_service,
      active  => $activate_service,
      require => [Package['podman'], Podman::Container::User[$name]],
    }
  } else {
    Systemd::Unit_file["${unique_name}.service"] {
      enable => false,
      active => false,
    }
  }

}
