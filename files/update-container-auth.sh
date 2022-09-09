#!/bin/bash

user=$1

if [ -z "${user}" ]; then
  echo "USAGE: $0 USER"
  exit 1
fi

if [ ! -d "/var/lib/containers/users/${user}/data" ]; then
  echo "User ${user} is not setup for containers, no such directory at /var/lib/containers/users/${user}/data"
  exit 1
fi

/usr/local/bin/container-yaml-auth-to-authfile.rb $(cat /var/lib/containers/users/${user}/data/auth_files.args) > "/var/lib/containers/users/${user}/data/auth.json"

chmod 0600 "/var/lib/containers/users/${user}/data/auth.json"

uid=$(uid -u $user)
cp -a "/var/lib/containers/users/${user}/data/auth.json" "/run/pods/${uid}/containers/auth.json"
