# pulls an image
define podman::image(
  String[1,32]
    $user,
  Integer
    $uid,
  Stdlib::Compat::Absolute_Path
    $homedir,
  Pattern[/^[\S]*$/]
    $image = $title,
  Optional[String[1,32]]
    $group = undef,
) {
  if $image =~ /:/ {
    $image_str = $image
  } else {
    $image_str = "${image}:latest"
  }
  if $group {
    $real_group = $group
  } else {
    $real_group = $user
  }
  Podman::Container::User<| title == $user |> -> exec{"podman_image_${name}":
    command     => "podman pull ${image_str}",
    unless      => "podman image exists ${image_str}",
    user        => $user,
    group       => $real_group,
    cwd         => $homedir,
    environment => ["HOME=${homedir}",
                    "XDG_RUNTIME_DIR=/run/pods/${uid}"],
    path        => ['/bin', '/usr/bin', '/usr/local/bin'],
  }
}
