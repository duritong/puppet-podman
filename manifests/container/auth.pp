# manages an auth file
define podman::container::auth (
  Podman::Auth $auth,
  Stdlib::Unixpath $path,
  String[1] $user,
  String[1] $group,
  String[1] $owner = 'root',
  Stdlib::Filemode $mode = '0440',
  Pattern[/^\d{3}$/] $order = '050',
  String[1] $con_name = $title,
  Boolean $replace = true,
) {
  file {
    $path:
      content => epp('podman/auth-file.yaml.epp', { auth => $auth, $name => $con_name }, ),
      replace => $replace,
      owner   => $owner,
      group   => $group,
      mode    => $mode,
      notify  => Exec["init-podman-auth-file-${user}"];
  } -> concat::fragment { "podman-auth-files-${user}-${name}":
    order   => $order,
    target  => "podman-auth-files-${user}", # no newline!
    content => "${path} ",
  }
}
