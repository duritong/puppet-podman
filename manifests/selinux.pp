# manages selinux related things to podman
class podman::selinux {
  # some containers want to use this
  selboolean { 'virt_sandbox_use_netlink':
    persistent => true,
    value      => on,
    before     => Package['podman'],
  }
  file {
    default:
      ensure  => directory,
      owner   => root,
      group   => 0,
      mode    => '0644',
      recurse => true,
      purge   => true,
      force   => true,
      seltype => 'container_var_lib_t';
    '/var/lib/containers/selinux':;
    '/var/lib/containers/selinux/templates':
      source  => 'puppet:///modules/podman/selinux/templates',
  }
}
