# for sidecars where apache connects to
class podman::selinux::policy::socat_httpd_sidecar {
  podman::selinux::policy{
    'socat_httpd_sidecar':
      templates => ['base_container']
  }
}
