# manages a user that runs a container
define podman::container::user(
  Variant[String[1],Integer]
                           $uid,
  Variant[String[1],Integer]
                           $gid,
  Stdlib::Compat::Absolute_Path
                           $homedir,
  Stdlib::Filemode         $homedir_mode = '0750',
  String[1]                $group        = $name,
  Enum['present','absent'] $ensure       = 'present',
  Boolean                  $managehome   = true,
){
  file{
    "/var/lib/containers/users/${name}":
  }
  user::managed{
    $name:
      ensure       => $ensure,
      uid          => $uid,
      gid          => $gid,
      name_comment => "Container ${name}",
      managehome   => $managehome,
      homedir      => $homedir,
      homedir_mode => $homedir_mode,
      shell        => '/sbin/nologin',
  }

  if $ensure == 'present' {
    File["/var/lib/containers/users/${name}"]{
      ensure  => directory,
      owner   => $name,
      group   => $name,
      mode    => '0640',
      require => User[$name],
    } -> file{
      [ "/var/lib/containers/users/${name}/storage",
      "${homedir}/.config",
      "${homedir}/.config/containers", ]:
        ensure => directory,
        owner  => $name,
        group  => $name,
        mode   => '0640';
      "${homedir}/.config/containers/storage.conf":
        content => template('podman/users-storage.conf.erb'),
        owner  => $name,
        group  => $name,
        mode   => '0640';
    }
  } else {
    File["/var/lib/containers/users/${name}"]{
      ensure  => absent,
      purge   => true,
      force   => true,
      recurse => true,
    }
  }

}
