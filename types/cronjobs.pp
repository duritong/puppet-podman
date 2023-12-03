type Podman::Cronjobs = Hash[
  Pattern[/^[a-zA-Z0-9_\-]+$/],
  Struct[{
      ensure               => Optional[Enum['present','absent']],
      container_name       => Optional[String[1]],
      cmd                  => String[1],
      on_calendar          => Optional[String],
      randomized_delay_sec => Optional[String],
      trigger_restart      => Optional[Boolean],
  }]
]
