# Manages containers using podman
#
# @summary Run rootless containers on EL hosts
#
# @example
#   include podman
class podman(
  $size_container_disk = '5G',
  $containers          = {},
) {
  sysctl::value{
    'user.max_user_namespaces':
      value => '28633'
  } -> package{
    [ 'slirp4netns', 'podman','runc' ]:
      ensure => installed,
  } -> User<| title != 'root' |>

  # have our own tmpdirs and make it short as sockets
  # go into that dir, which can have limited length
  # https://github.com/containers/libpod/issues/4057
  systemd::tmpfile{
    "podman_tmp.conf":
      content => "d /run/pods 711 root root",
      require => Package['podman'];
  }

  if $size_container_disk {
    disks::lv_mount{
      'containers_lv':
        folder  => '/var/lib/containers',
        owner   => 'root',
        group   => 'root',
        mode    => '0711',
        size    => $size_container_disk,
        fs_type => 'xfs',
        seltype => 'container_var_lib_t',
        #  before  => Selinux::Fcontext['/var/lib/containers/users(/.*)?'],
    }
  }
  #  selinux::fcontext{
  #    '/var/lib/containers/users(/.*)?':
  #      setype => 'data_home_t',
  #  } -> file{
  file{
    '/var/lib/containers/users':
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0711',
      #    seltype => 'data_home_t',
      before  => Package['podman'];
  }

  $containers.each |$n,$con| {
    podman::container{
      $n:
        * => $con,
    }
  }
}
