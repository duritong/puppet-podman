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
                           $homedir        = undef,
){
  if $homedir {
    $real_homedir = $homedir
  } else {
    $real_homedir = "/home/${user}"
  }
  include ::podman
  $sanitised_title = regsubst($title, '[^0-9A-Za-z.\-_]', '-', 'G')
  podman::container::user{
    $user:
      group   => $group,
      uid     => $uid,
      gid     => $gid,
      ensure  => $ensure,
      homedir => $real_homedir,
  } -> systemd::unit_file{
    "${container_name}.service":
      content => template('podman/user-container.service'),
      enable  => true,
      active  => true,
      require => Package['podman'],
  }
}
