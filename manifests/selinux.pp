# manages selinux related things to podman
class podman::selinux {
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
      source  => 'puppet:///modules/podman/selinux/templates',
      owner   => root,
      group   => 0,
      mode    => '0644',
      recurse => true,
      purge   => true,
      force   => true;
  }
}
