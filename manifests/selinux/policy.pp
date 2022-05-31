# manages a dedicated container policy
define podman::selinux::policy (
  $templates = [],
) {
  include podman::selinux

  if versioncmp($facts['os']['release']['major'],'8') < 0 {
    $template_files = $templates.map |$x| { "/var/lib/containers/selinux/templates/${x}.cil" }
  } else {
    $template_files = $templates.map |$x| { "/usr/share/udica/templates/${x}.cil" }
  }
  $template_files_str = $template_files.join(' ')

  file {
    "/var/lib/containers/selinux/${name}.cil":
      source => "puppet:///modules/podman/selinux/container_modules/${name}.cil",
      owner  => root,
      group  => 0,
      mode   => '0644',
  } ~> exec { "install_selinux_container_policy_${name}":
    command     => "semodule -i /var/lib/containers/selinux/${name}.cil ${template_files_str}",
    refreshonly => true,
    subscribe   => File['/var/lib/containers/selinux/templates'],
  } -> exec { "ensure_selinux_container_policy_${name}": # mainly for future runs, so we don't miss it if it's not working
    command => "semodule -i /var/lib/containers/selinux/${name}.cil ${template_files_str}",
  }
  if versioncmp($facts['os']['release']['major'],'8') < 0 {
    Exec["ensure_selinux_container_policy_${name}"]{
      creates => "/etc/selinux/targeted/active/modules/400/${name}",
    }
  } else {
    Exec["ensure_selinux_container_policy_${name}"]{
      creates => "/var/lib/selinux/targeted/active/modules/400/${name}",
    }
  }
}
