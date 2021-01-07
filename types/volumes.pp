type Podman::Volumes = Variant[
  Hash[
    Variant[Stdlib::Unixpath, String[1]],
    Stdlib::Unixpath
  ],
  Array[Pattern[/^\/.*:\/[^:]*(:(ro|rw|Z)(,Z)?)?/]]
]
