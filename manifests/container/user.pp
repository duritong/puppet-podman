# manages a user that runs a container
define podman::container::user (
  Variant[String[1],Integer] $uid,
  Stdlib::Compat::Absolute_Path $homedir,
  Variant[String[1],Integer] $gid = 'uid',
  Enum['present','absent'] $ensure = 'present',
  Stdlib::Filemode $homedir_mode = '0750',
  String[1] $group = $name,
  Boolean $managehome = true,
  Boolean $manage_user = true,
) {
  file {
    "/var/lib/containers/users/${name}":
      seltype => 'data_home_t',
  }
  if $manage_user and !defined(User::Managed[$name]) {
    user::managed {
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
  systemd::tmpfile {
    "podman_tmp_${name}.conf":
      content => "d /run/pods/${uid} 700 ${name} ${group}\nd /run/pods/${uid}/containers 700 ${name} ${group}";
  }
  $image_lifecycle_cron = "/etc/cron.daily/podman-${name}-image-lifecycle.sh"
  concat {
    $image_lifecycle_cron:
      ensure => $ensure,
      owner  => root,
      group  => 0,
      mode   => '0700',
  }
  if $ensure == 'present' {
    User::Managed[$name] -> Concat[$image_lifecycle_cron]
    concat::fragment {
      "image-lifecycle-cron-${name}-header":
        target  => $image_lifecycle_cron,
        content => "#!/bin/bash\n",
        order   => '00';
      "image-lifecycle-cron-${name}-finalize":
        target  => $image_lifecycle_cron, # yes is workaround for https://github.com/containers/libpod/issues/4844
        content => "su - ${name} -s /bin/bash -c \"yes y | podman system prune -a\" > /dev/null\n",
        order   => '99';
    }
    if versioncmp($facts['os']['release']['major'],'7') > 0 {
      loginctl_user { $name:
        linger  => enabled,
        require => User::Managed[$name],
      }
      file {
        "${homedir}/.config/containers/containers.conf":
          content => epp('podman/users-containers.conf.epp', { user => $name }),
          owner   => $name,
          group   => $group,
          mode    => '0640',
          before  => Exec["init-podman-config-${name}"],
          require => File["/var/lib/containers/users/${name}/tmpdir"];
      }
    }

    file {
      "${homedir}/.bash_profile":
        content => "[[ -r ~/.bashrc ]] && . ~/.bashrc\n",
        owner   => 'root',
        group   => $group,
        mode    => '0640';
      "${homedir}/.bashrc":
        content => "export XDG_RUNTIME_DIR=/run/pods/${uid}\nexport REGISTRY_AUTH_FILE=/var/lib/containers/users/${name}/data/auth.json",
        owner   => 'root',
        group   => $group,
        mode    => '0640';
    } -> File["/var/lib/containers/users/${name}"] {
      ensure => directory,
      owner  => $name,
      group  => $group,
      mode   => '0751',
    } -> file {
      "/var/lib/containers/users/${name}/storage":
        ensure => directory,
        owner  => $name,
        group  => $group,
        mode   => '0751';
      "/var/lib/containers/users/${name}/data":
        ensure  => directory,
        owner   => 'root',
        group   => $group,
        seltype => 'data_home_t',
        mode    => '0640';
      "/var/lib/containers/users/${name}/tmpdir":
        ensure  => directory,
        owner   => $name,
        group   => $group,
        seltype => 'tmp_t',
        mode    => '0600';
      "/var/lib/containers/users/${name}/bin":
        ensure  => directory,
        owner   => 'root',
        group   => $group,
        seltype => 'container_runtime_exec_t',
        mode    => '0640';
      # lint:ignore:strict_indent
      ["${homedir}/.local",
      "${homedir}/.local/share",
      "${homedir}/.local/share/containers",
      "${homedir}/.config",
      "${homedir}/.cache",
      "${homedir}/.config/containers",]:
      # lint:endignore
        ensure => directory,
        owner  => $name,
        group  => $group,
        mode   => '0640';
      "${homedir}/.config/containers/storage.conf":
        content => template('podman/users-storage.conf.erb'),
        owner   => $name,
        group   => $group,
        mode    => '0640',
        before  => Exec["init-podman-config-${name}"];
    }
    File["/var/lib/containers/users/${name}/storage"] {
      seltype => 'data_home_t',
    }
    File["/var/lib/containers/users/${name}/bin","/var/lib/containers/users/${name}/data"] {
      purge   => true,
      recurse => true,
      force   => true,
    }
    if versioncmp($facts['os']['release']['major'],'8') > 0 {
      $test_file = "/var/lib/containers/users/${name}/storage/defaultNetworkBackend"
    } else {
      $test_file = "/var/lib/containers/users/${name}/storage/libpod/bolt_state.db"
    }
    exec {
      "init-podman-config-${name}":
        command     => 'podman info',
        creates     => $test_file,
        user        => $name,
        group       => $group,
        cwd         => $homedir,
        # lint:ignore:strict_indent
        require     => [File["${homedir}/.config/containers"],
                        Exec['systemd-tmpfiles']],
        # lint:endignore
        environment => ["HOME=${homedir}", "XDG_RUNTIME_DIR=/run/pods/${uid}"],
    } -> concat { "podman-auth-files-${name}":
      path    => "/var/lib/containers/users/${name}/data/auth_files.args",
      owner   => 'root',
      group   => $group,
      mode    => '0440',
      seltype => 'container_var_lib_t';
    } -> file { "/var/lib/containers/users/${name}/data/auth.json":
      ensure  => file,
      owner   => $name,
      group   => $group,
      mode    => '0600',
      seltype => 'container_var_lib_t';
    } -> exec { "update-podman-auth-file-${name}":
      command     => "/usr/local/bin/update-container-auth.sh ${name}",
      user        => $name,
      group       => $group,
      refreshonly => true,
      subscribe   => Concat["podman-auth-files-${name}"],
    }
  } else {
    Concat[$image_lifecycle_cron] -> User::Managed[$name]
    Systemd::Tmpfile["podman_tmp_${name}.conf"] {
      ensure => absent,
    }
    exec { "cleanup_podman_users_${name}":
      command => "rm -rf /var/lib/containers/users/${name}",
      onlyif  => "test -d /var/lib/containers/users/${name}",
    } -> File["/var/lib/containers/users/${name}"] {
      ensure  => absent,
      purge   => true,
      force   => true,
      recurse => true,
    }
  }
}
