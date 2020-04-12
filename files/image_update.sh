#!/bin/bash
#
# Pulls a container image.
# Returns 0 if there a change.
# Returns 2 if there is no change.
# Returns 3 if something when wrong.
#
CONTAINER_IMAGE="$1"

if [ -z "${CONTAINER_IMAGE}" ]; then
  echo "Error no image passed"
  exit 1
fi

# we default the label to latest
if [[ ! "${CONTAINER_IMAGE}" =~ : ]]; then
  CONTAINER_IMAGE="${CONTAINER_IMAGE}:latest"
fi

BEFORE="$(podman inspect --type image --format='{{.Id}}' "${CONTAINER_IMAGE}" 2>/dev/null)"
podman pull "${CONTAINER_IMAGE}"
AFTER="$(podman inspect --type image --format='{{.Id}}' "${CONTAINER_IMAGE}" 2>/dev/null)"

if [ -z "$AFTER" ]; then
  echo "Container image ${CONTAINER_IMAGE} failed to pull!"
  exit 3
elif [ "$BEFORE" == "$AFTER" ]; then
  echo "No updates to ${CONTAINER_IMAGE} available. Currently on ${AFTER}."
  exit 2
else
  echo "${CONTAINER_IMAGE} updated. Changed from ${BEFORE} to ${AFTER}."
  exit 0
fi
