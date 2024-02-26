# pulls an image
define podman::image (
  String[1,32] $user,
  Integer $uid,
  Stdlib::Absolutepath $homedir,
  Pattern[/^[\S]*$/] $image = $title,
  Optional[String[1,32]] $group = undef,
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
  # we are using the actual command in unless so it's run always
  # lint:ignore:strict_indent
  Podman::Container::User<| title == $user |> -> exec { "podman_image_${name}":
    command     => "/usr/local/bin/container-update-image.sh ${image_str}",
    unless      => "podman images -q ${image_str} | grep .",
    timeout     => 3600,
    user        => $user,
    returns     => ['0', '2'],
    group       => $real_group,
    cwd         => $homedir,
    environment => ["HOME=${homedir}",
                    "XDG_RUNTIME_DIR=/run/pods/${uid}",
                    "REGISTRY_AUTH_FILE=/var/lib/containers/users/${user}/data/auth.json"],
  }
  # lint:endignore
}
