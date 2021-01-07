# for most containers for webhostings
class podman::selinux::policy::httpd_container_rw_content {
  podman::selinux::policy {
    'httpd_container_rw_content':
      templates => ['base_container', 'net_container'],
  }
}
