type Podman::Auth = Hash[
  Pattern[/^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])(:\d+)?$/],
  Struct[{
      user => Pattern[/^[a-zA-Z0-9_\.@\-]+$/],
      password => Pattern[/^[a-zA-Z0-9\|\+\.\*\%\_]+$/],
  }]
]
