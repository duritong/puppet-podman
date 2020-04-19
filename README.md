# podman

Manages container with podman.

## Dependencies

### Hard dependencies

* [concat](https://forge.puppet.com/puppetlabs/concat)
* [selinux](https://code.immerda.ch/immerda/puppet-modules/selinux)
* [stdlib](https://forge.puppet.com/puppetlabs/stdlib)
* [sysctl](https://forge.puppet.com/duritong/sysctl)
* [systemd](https://forge.puppet.com/camptocamp/systemd)
* [user](https://code.immerda.ch/immerda/puppet-modules/user)

### Soft dependencies

* [disks](https://code.immerda.ch/immerda/puppet-modules/disks)
* [rkhunter](https://code.immerda.ch/immerda/puppet-modules/rkhunter)
* [rsyslog](https://code.immerda.ch/immerda/puppet-modules/rsyslog)

## Known bugs

* CentOS does generate subuids and subgids only if the user isn't a system user.
  Use uids and gids higher than 1000 is highly recommended.

## Hiera example

Simple example, start an nginx.
```Yaml
podman::size_container_disk: false
podman::use_rkhunter: false
podman::containers:
  example_com:
    user: example_com
    uid: 2000
    gid: 2000
    image: docker.io/nginx
    use_rsyslog: false
    publish:
      - '8080:80'
    volumes:
      /var/www/html: '/usr/share/nginx/html:ro,Z'
```

Start an UniFi controller with storage, port expose and everything needed.
```Yaml
podman::size_container_disk: false
podman::use_rkhunter: false
podman::containers:
  unifi:
    user: podman-unifi
    uid: 2000
    gid: 2000
    image: docker.io/linuxserver/unifi-controller
    use_rsyslog: false
    envs:
      - 'PUID=1000'
      - 'PGID=1000'
      - 'MEM_LIMIT=1024M'
    publish:
      - '3478:3478/udp'
      - '10001:10001/udp'
      - '8080:8080'
      - '8081:8081'
      - '8443:8443'
      - '8843:8843'
      - '8880:8880'
      - '6789:6789'
    volumes:
      /srv/unifi: '/config:Z'
```
