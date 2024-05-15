# for most containers for webhostings
class podman::selinux::policy::httpd_container_rw_content_direct_socket {
  podman::selinux::policy {
    'httpd_container_rw_content_direct_socket':
      templates => ['base_container', 'net_container'],
  }
}
