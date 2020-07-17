#!/usr/bin/env bash

set -e

source "${SNAP}/actions/common/utils.sh"

echo "Enabling ZFS..."

if [ -f "${SNAP_DATA}/args/zfs-volumes" ]
then
  echo "ZFS is already enabled."
else
  echo "WARNING: This will stop microk8s and remove all pods!"
  read -p "Do you want to continue? [y/n] " -n 1 -r 
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    echo "ZFS was not enabled."
    exit 1
  fi
  RPOOL_CHECK=$(run_with_sudo "${SNAP}/sbin/zpool" list -o name | grep "^rpool$" ) || true
  if [ -n "${RPOOL_CHECK}" ]
  then 
    VOLUME=rpool/microk8s/snapshotter
  else
    VOLUME=
  fi
  echo "Where would you like the ZFS shapshotter volume created: "
  read -p "[${VOLUME}] "
  if [ -n "${REPLY}" ]
  then
    VOLUME=${REPLY}
    POOL=$(echo ${VOLUME} | sed 's#/.*##')
    POOL_CHECK=$(run_with_sudo "${SNAP}/sbin/zpool" list -o name | grep "^${POOL}$" ) || true
    if [ -z "${POOL_CHECK}" ]
    then
      echo "ZFS pool \"${POOL}\" does not exist!"
      echo "ZFS was not enabled."
      exit 1
    fi
  fi
  echo Stopping microk8s
  run_with_sudo preserve_env snapctl stop "${SNAP_NAME}"
  echo reconfiguring containerd
  run_with_sudo sed -i 's/snapshotter =.*/snapshotter = "zfs"/' "${SNAP_DATA}/args/containerd-template.toml"
  echo removing all existing data
  run_with_sudo rm -rf "${SNAP_COMMON}/var/lib/containerd/*"
  echo "creating ZFS volume ${VOLUME}"
  run_with_sudo "${SNAP}/sbin/zfs" create -p -o "mountpoint=${SNAP_COMMON}/var/lib/containerd/io.containerd.snapshotter.v1.zfs" "${VOLUME}"
  run_with_sudo "${SNAP}/sbin/zfs" set com.sun:auto-snapshot=false "${VOLUME}"

  echo "$VOLUME" >> "${SNAP_DATA}/args/zfs-volumes"

  # switch containerd log level fatal to avoid excessive log spam since zfs snapshotter does not support Usage
  # https://github.com/ubuntu/microk8s/issues/1077
  # https://github.com/containerd/zfs/issues/17
  echo "--log-level fatal" >> "${SNAP_DATA}/args/containerd"

  echo "restarting microk8s"
  run_with_sudo preserve_env snapctl start "${SNAP_NAME}"
  echo "Waiting for microk8s to restart."
  "${SNAP}/microk8s-status.wrapper" --wait-ready >/dev/null
  echo "ZFS is enabled"
fi
