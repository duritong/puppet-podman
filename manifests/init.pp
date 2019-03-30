# A description of what this class does
#
# @summary A short summary of the purpose of this class
#
# @example
#   include podman
class podman(
  $size_container_disk = '5G',
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
    exec{'curl -o /etc/yum.repos.d/vbatts-shadow-utils-newxidmap-epel-7.repo https://copr.fedorainfracloud.org/coprs/vbatts/shadow-utils-newxidmap/repo/epel-7/vbatts-shadow-utils-newxidmap-epel-7.repo':
      creates => '/etc/yum.repos.d/vbatts-shadow-utils-newxidmap-epel-7.repo'
    } -> file{'/etc/yum.repos.d/vbatts-shadow-utils-newxidmap-epel-7.repo':
      ensure => present,
    } -> package{'shadow-utils46-newxidmap':
      ensure => installed
    } -> Sysctl::Value['user.max_user_namespaces']
  }

  if $size_container_disk {
    disks::lv_mount{
      'container_lv':
        folder  => '/var/lib/container',
        owner   => 'root',
        group   => 'root',
        mode    => '0711',
        size    => $size_container_disk,
        fs_type => 'xfs',
        seltype => 'container_var_lib_t',
    } -> selinux::fcontext{
      '/var/lib/container/users(/.*)?':
        setype => 'data_home_t',
    } -> file{
      '/var/lib/container/users':
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0711',
        seltype => 'data_home_t',
        before  => Package['podman'];
    }
  }
}
