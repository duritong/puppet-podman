#!/bin/bash

# Pulls all images of a pod

# Returns 0 if there a change.
# Returns 2 if there is no change.
# Returns 3 if something when wrong.

if [ -f "$1" ]; then
  ret=2
  while read -r image; do
    /usr/local/bin/container-update-image.sh "$image"
    cr="$?"
    if [ "$cr" -eq 0 ]; then
      ret=0
    elif [ "$cr" -ne 2 ]; then
      echo "Something went wrong while fetching ${image} - please check previous output"
      exit "$cr"
    fi
  done < <(grep -E '^\s{4}image: ' "$1"  | sed 's/.*image:\s*//')
  exit "$ret"
else
  echo "No such file ${1}!"
  echo "USAGE: ${0} /path/to/pod.yaml"
  exit 4
fi
