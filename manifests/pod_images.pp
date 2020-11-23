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
  $onlyif_cmd_prefix = 'bash -xe -c \"grep \' image: \''
  # lint:ignore:single_quote_string_with_variables
  $onlyif_cmd_suffix = '| sed \'s/.* image:\s*//\' | while read -r line; do podman images -q "\\${line}" | grep .; done"'
  # lint:endignore
  Podman::Container::User<| title == $user |> -> exec{"podman_pod_${name}":
    command     => "/usr/local/bin/pod-update-image.sh ${pod_yaml}",
    onlyif      => "${onlyif_cmd_prefix} ${pod_yaml} ${onlyif_cmd_suffix}",
    timeout     => 3600,
    user        => $user,
    returns     => ['0', '2'],
    group       => $real_group,
    cwd         => $homedir,
    environment => ["HOME=${homedir}",
                    "XDG_RUNTIME_DIR=/run/pods/${uid}",
                    "REGISTRY_AUTH_FILE=/var/lib/containers/users/${user}/data/auth.json"],
  }
}
