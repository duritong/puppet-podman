# A description of what this class does
#
# @summary A short summary of the purpose of this class
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
  } -> concat{
    ['/etc/subuid','/etc/subgid' ]:
      owner => 'root',
      group => 'root',
      mode  => '0644',
  } -> package{
    [ 'slirp4netns', 'podman','runc' ]:
      ensure => installed,
  }

  if versioncmp($facts['os']['release']['full'],'7.7') < 0 {
    package{'shadow-utils46-newxidmap':
      ensure => installed,
      before => Sysctl::Value['user.max_user_namespaces'],
    }
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
        before  => Selinux::Fcontext['/var/lib/containers/users(/.*)?'],
    }
  }
  selinux::fcontext{
    '/var/lib/containers/users(/.*)?':
      setype => 'data_home_t',
  } -> file{
    '/var/lib/containers/users':
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0711',
      seltype => 'data_home_t',
      before  => Package['podman'];
  }

  $containers.each |$n,$con| {
    podman::container{
      $n:
        * => $con,
    }
  }
}
