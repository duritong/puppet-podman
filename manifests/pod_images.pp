# pulls an image
define podman::pod_images(
  String[1,32]
    $user,
  Integer
    $uid,
  Stdlib::Compat::Absolute_Path
    $homedir,
  Stdlib::Unixpath
    $pod_yaml = $title,
  Optional[String[1,32]]
    $group = undef,
) {
  if $group {
    $real_group = $group
  } else {
    $real_group = $user
  }
  # we are using the actual command in unless so it's run always
  Podman::Container::User<| title == $user |> -> exec{"podman_pod_${name}":
    command     => "echo 'Update of pod ${pod_yaml} complete'",
    onlyif      => "/usr/local/bin/pod-update-image.sh ${pod_yaml}",
    timeout     => 3600,
    user        => $user,
    returns     => ['0', '2'],
    group       => $real_group,
    cwd         => $homedir,
    environment => ["HOME=${homedir}",
                    "XDG_RUNTIME_DIR=/run/pods/${uid}"],
  }
}
