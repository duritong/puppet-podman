type Podman::Socketports = Hash[
  Stdlib::Port,
  Struct[{
      dir                       => Optional[Stdlib::Unixpath],
      mode                      => Optional[Stdlib::Filemode],
      'security-opt-label-type' => Optional[String[1]]
  }],
]
