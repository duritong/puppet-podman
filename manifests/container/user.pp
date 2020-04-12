# manages a user that runs a container
define podman::container::user(
  Variant[String[1],Integer]
                            $uid,
  Stdlib::Compat::Absolute_Path
                            $homedir,
  Variant[String[1],Integer]
                            $gid          = 'uid',
  Enum['present','absent']  $ensure       = 'present',
  Stdlib::Filemode          $homedir_mode = '0750',
  String[1]                 $group        = $name,
  Boolean                   $managehome   = true,
  Boolean                   $manage_user  = true,
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
  $image_lifecycle_cron = "/etc/cron.daily/podman-${name}-image-lifecycle.sh"
  concat{
    $image_lifecycle_cron:
      ensure => $ensure,
      owner  => root,
      group  => 0,
      mode   => '0700',
  }
  if $ensure == 'present' {
    User::Managed[$name] -> Concat[$image_lifecycle_cron]
    concat::fragment{
      "image-lifecycle-cron-${name}-header":
        target  => $image_lifecycle_cron,
        content => '#!/bin/bash',
        order   => '00';
      "image-lifecycle-cron-${name}-finalize":
        target  => $image_lifecycle_cron, # yes is workaround for https://github.com/containers/libpod/issues/4844
        content => "su - ${name} -s /bin/bash -c \"yes y | podman system prune -a\" > /dev/null",
        order   => '99';
    }

    file{
      "${homedir}/.bash_profile":
        content => "[[ -r ~/.bashrc ]] && . ~/.bashrc\n",
        owner   => 'root',
        group   => $name,
        mode    => '0640';
      "${homedir}/.bashrc":
        content => "export XDG_RUNTIME_DIR=/run/pods/${uid}\n",
        owner   => 'root',
        group   => $name,
        mode    => '0640';
    } -> File["/var/lib/containers/users/${name}"]{
      ensure => directory,
      owner  => $name,
      group  => $name,
      mode   => '0751',
    } -> file{
      "/var/lib/containers/users/${name}/storage":
        ensure => directory,
        owner  => $name,
        group  => $name,
        mode   => '0751';
      "/var/lib/containers/users/${name}/bin":
        ensure  => directory,
        owner   => 'root',
        group   => $name,
        seltype => 'container_runtime_exec_t',
        mode    => '0640';
      [ "${homedir}/.local",
      "${homedir}/.local/share",
      "${homedir}/.local/share/containers",
      "${homedir}/.config",
      "${homedir}/.config/containers", ]:
        ensure => directory,
        owner  => $name,
        group  => $name,
        mode   => '0640';
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
        command     => 'podman info',
        creates     => "/var/lib/containers/users/${name}/storage/libpod/bolt_state.db",
        user        => $name,
        group       => $name,
        cwd         => $homedir,
        require     => [File["${homedir}/.config/containers"],
                        Exec[systemd-tmpfiles] ],
        environment => ["HOME=${homedir}",
                        "XDG_RUNTIME_DIR=/run/pods/${uid}"],
    }
  } else {
    Concat[$image_lifecycle_cron] -> User::Managed[$name]
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
