# manages a user that runs a container
define podman::container::user(
  Variant[String[1],Integer]
                           $uid,
  Stdlib::Compat::Absolute_Path
                           $homedir,
  Variant[String[1],Integer]
                           $gid          = 'uid',
  Enum['present','absent'] $ensure       = 'present',
  Stdlib::Filemode         $homedir_mode = '0750',
  String[1]                $group        = $name,
  Boolean                  $managehome   = true,
  Boolean                  $manage_user  = true,
){
  file{
    "/var/lib/containers/users/${name}":
      seltype => 'data_home_t',
  }
  if $manage_user and !defined(User::Managed[$name]) {
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
  }

  # https://github.com/containers/libpod/issues/4057
  systemd::tmpfile{
    "podman_tmp_${name}.conf":
      content => "d /run/pods/${uid} 700 ${name} ${name}";
  }
  if $ensure == 'present' {
    file{
      "${homedir}/.bashrc":
        content => "XDG_RUNTIME_DIR=/run/pods/${uid}\n",
        owner   => root,
        group   => $name,
        mode    => '0640';
    } -> File["/var/lib/containers/users/${name}"]{
      ensure  => directory,
      owner   => $name,
      group   => $name,
      mode    => '0751',
    } -> file{
      "/var/lib/containers/users/${name}/storage":
        ensure  => directory,
        owner   => $name,
        group   => $name,
        mode    => '0751';
      "/var/lib/containers/users/${name}/bin":
        ensure  => directory,
        owner   => 'root',
        group   => $name,
        mode    => '0640';
      [ "${homedir}/.local",
      "${homedir}/.local/share",
      "${homedir}/.local/share/containers",
      "${homedir}/.config",
      "${homedir}/.config/containers", ]:
        ensure  => directory,
        owner   => $name,
        group   => $name,
        mode    => '0640';
      "${homedir}/.config/containers/storage.conf":
        content => template('podman/users-storage.conf.erb'),
        owner   => $name,
        group   => $name,
        mode    => '0640';
    }
    File["/var/lib/containers/users/${name}/storage"]{
      seltype => 'data_home_t',
    }
    File["/var/lib/containers/users/${name}/bin"]{
      purge   => true,
      recurse => true,
      force   => true,
    }
    exec{
      "init-podman-config-${name}":
        command => "podman info",
        creates => "${homedir}/.config/containers/libpod.conf",
        user    => $name,
        group   => $name,
        cwd     => $homedir,
        require => [ File["${homedir}/.config/containers"],
                        Exec[systemd-tmpfiles] ],
        environment => ["HOME=${homedir}",
                        "XDG_RUNTIME_DIR=/run/pods/${uid}"],
    }
  } else {
    Systemd::Tmpfile["podman_tmp_${name}.conf"]{
      ensure => absent,
    }
    File["/var/lib/containers/users/${name}"]{
      ensure  => absent,
      purge   => true,
      force   => true,
      recurse => true,
    }
  }

}
