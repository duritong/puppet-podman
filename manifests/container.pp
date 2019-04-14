# manages a running container
define podman::container(
  String[1,30]             $user,
  Pattern[/^[\S]*$/]       $image,
  Variant[String[1],Integer]
                           $uid,
  Variant[String[1],Integer]
                           $gid,
  String[1]                $group = $user,
  Enum['present','absent'] $ensure = 'present',
  String                   $container_name = $title,
  Boolean                  $manage_user    = true,
  Optional[String]         $command        = undef,
  Optional[Stdlib::Compat::Absolute_Path]
                           $home_dir       = undef,
){
  if $home_dir {
    $real_home_dir = $home_dir
  } else {
    $real_home_dir = "/home/${user}"
  }
  include ::podman
  $sanitised_title = regsubst($title, '[^0-9A-Za-z.\-_]', '-', 'G')
  podman::container::user{
    $user:
      group    => $group,
      uid      => $uid,
      gid      => $gid,
      ensure   => $ensure,
      home_dir => $real_home_dir,
  } -> systemd::unit_file{
    "${container_name}.service":
      content => template('podman/user-container.service'),
      enable  => true,
      active  => true,
      require => Package['podman'],
  }
}
