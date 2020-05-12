# manages selinux related things to podman
class podman::selinux {
  # some containers want to use this
  selboolean { 'virt_sandbox_use_netlink':
    persistent => true,
    value      => on,
    before     => Package['podman'],
  }
  file{
    '/var/lib/containers/selinux':
      ensure  => directory,
      owner   => root,
      group   => 0,
      mode    => '0644',
      recurse => true,
      purge   => true,
      force   => true;
    '/var/lib/containers/selinux/templates':
      ensure  => directory,
      source  => 'puppet:///modules/podman/selinux/templates',
      owner   => root,
      group   => 0,
      mode    => '0644',
      recurse => true,
      purge   => true,
      force   => true;
  }
}
