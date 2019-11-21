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
) {
  if $image =~ /:/ {
    $image_str = $image
  } else {
    $image_str = "${image}:latest"
  }
  Podman::Container::User<| title == $user |> -> exec{"podman_image_${name}":
    command     => "podman pull ${image_str}",
    unless      => "podman image exists ${image_str}",
    user        => $user,
    group       => $user,
    cwd         => $homedir,
    environment => ["HOME=${homedir}",
                     "XDG_RUNTIME_DIR=/run/pods/${uid}"],
  }
}
