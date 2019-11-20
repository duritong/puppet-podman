# manages a running container
define podman::container(
  String[1,30]             $user,
  Pattern[/^[\S]*$/]       $image,
  Variant[String[1],Integer]
                           $uid,
  Variant[String[1],Integer]
                           $gid,
  String[1]                $group       = $user,
  Enum['present','absent'] $ensure      = 'present',
  String                   $container_name          = $title,
  Boolean                  $pull_image_before_start = false,
  Optional[String]         $command     = undef,
  Array[Pattern[/^\d+:\d+/]]
                           $publish     = [],
  Hash[Stdlib::Compat::Absolute_Path,
    Stdlib::Compat::Absolute_Path]
                           $volumes     = {},
  Hash                     $run_flags   = {},
  Optional[Stdlib::Compat::Absolute_Path]
                           $homedir     = undef,
  Boolean                  $manage_user = true,
  Stdlib::Compat::Absolute_Path
                           $logpath     = '/var/log/containers',
){
  if $homedir {
    $real_homedir = $homedir
  } else {
    $real_homedir = "/home/${user}"
  }
  include ::podman
  $sanitised_title = regsubst($title, '[^0-9A-Za-z.\-_]', '-', 'G')
  if $run_flags['security-opt-label-type'] {
    require "podman::selinux::policy::${run_flags['security-opt-label-type']}"
    Class["podman::selinux::policy::${run_flags['security-opt-label-type']}"] -> Systemd::Unit_file["pod-${user}-${container_name}.service"]
  }

  $unique_name = "pod-${user}-${container_name}"
  rsyslog::confd{
    $unique_name:
      ensure  => $ensure,
      content => template('podman/rsyslog-confd.erb'),
  } -> logrotate::rule{
    $unique_name:
      ensure       => $ensure,
      path         => "${logpath}/${unique_name}.log",
      compress     => true,
      copytruncate => true,
      dateext      => true,
  }
  if !defined(Podman::Container::User[$user]) {
    podman::container::user{
      $user:
        ensure      => $ensure,
        manage_user => $manage_user,
        group       => $group,
        uid         => $uid,
        gid         => $gid,
        homedir     => $real_homedir,
        before      => File["/var/lib/containers/users/${user}/bin/${sanitised_title}.sh"],
    }
  }
  file{
    "/var/lib/containers/users/${user}/bin/${sanitised_title}.sh":
      ensure  => $ensure,
      content => template('podman/user-container.sh.erb'),
      owner   => $uid,
      group   => $gid,
      mode    => '0750';
  } ~> systemd::unit_file{
    "${unique_name}.service":
      ensure  => $ensure,
      content => template('podman/user-container.service.erb'),
      enable  => true,
      active  => true,
      require => Package['podman'],
  }
}
