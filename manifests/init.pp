# Manages containers using podman
#
# @summary Run rootless containers on EL hosts
#
# @example
#   include podman
class podman (
  $size_container_disk = '5G',
  $containers_lv       = 'containers_lv',
  $containers          = {},
  $use_rkhunter        = true,
  $cron_timer_defaults = {
    on_calendar         => 'daily',
    randomize_delay_sec => '1d',
  },
) {
  if versioncmp($facts['os']['release']['major'],'8') < 0 {
    selinux::policy {
      'podman-base':
        te_source => 'puppet:///modules/podman/selinux/podman-base.te',
        before    => Package['podman'],
    }
  }
  sysctl::value {
    'user.max_user_namespaces':
      value => '28633',
  } -> package {
    ['slirp4netns', 'podman']:
      ensure => installed,
  } -> User<| title != 'root' |>

  include yum::centos::disable_rhsmcertd
  Package['podman'] -> Class['yum::centos::disable_rhsmcertd']

  # have our own tmpdirs and make it short as sockets
  # go into that dir, which can have limited length
  # https://github.com/containers/libpod/issues/4057
  systemd::tmpfile {
    'podman_tmp.conf':
      content => 'd /run/pods 711 root root',
      require => Package['podman'];
  }

  selinux::fcontext {
    '/usr/local/bin/manage-user-pod\.rb':
      setype  => 'container_runtime_exec_t',
      require => Package['podman'];
  } -> file {
    default:
      owner => root,
      group => root,
      mode  => '0755';
    '/usr/local/bin/container-yaml-auth-to-authfile.rb':
      source => 'puppet:///modules/podman/yaml-to-authfile.rb';
    '/usr/local/bin/container-update-image.sh':
      source => 'puppet:///modules/podman/image_update.sh';
    '/usr/local/bin/pod-update-image.sh':
      source => 'puppet:///modules/podman/pod_image_update.sh';
    '/usr/local/bin/manage-user-pod.rb':
      seltype => 'container_runtime_exec_t',
      source  => 'puppet:///modules/podman/manage-user-pod.rb';
  }

  if $size_container_disk {
    disks::lv_mount {
      $containers_lv:
        folder  => '/var/lib/containers',
        owner   => 'root',
        group   => 'root',
        mode    => '0711',
        size    => $size_container_disk,
        fs_type => 'xfs',
        seltype => 'container_var_lib_t',
    }
  }
  selinux::fcontext {
    '/var/lib/containers/users/[^/]+/bin(/.*)?':
      setype  => 'container_runtime_exec_t',
      require => Package['podman'];
  } -> Podman::Container<| |>
  file {
    '/var/lib/containers/users':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0711',
      before => Package['podman'];
  }

  $containers.each |$n,$con| {
    podman::container {
      $n:
        * => $con,
    }
  }

  # no rkhunter yet on EL9
  if $use_rkhunter and versioncmp($facts['os']['release']['major'],'9') < 0 {
    # https://github.com/relud/puppet-lint-strict_indent-check/issues/20
    # lint:ignore:strict_indent
    $content = @(EOF)
ALLOWDEVFILE="/dev/shm/libpod_lock"
ALLOWDEVFILE="/dev/shm/libpod_rootless_lock_*"
| EOF
# lint:endignore
    rkhunter::local_conf {
      'podman':
        content => $content,
    }
  }
}
