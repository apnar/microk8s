#!/usr/bin/env bash

set -e

source "${SNAP}/actions/common/utils.sh"

echo "Disabling ZFS..."

if [ ! -f "${SNAP_DATA}/args/zfs-volumes" ]
then
  echo "ZFS is not enabled."
else
  echo "WARNING: This will stop microk8s and remove all pods!"
  read -p "Do you want to continue? [y/n] " -n 1 -r 
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    echo "ZFS was not disabled."
    exit 1
  fi
  echo Stopping microk8s
  run_with_sudo preserve_env snapctl stop "${SNAP_NAME}"
  echo reconfiguring containerd
  run_with_sudo sed -i 's/snapshotter =.*/snapshotter = "native"/' "${SNAP_DATA}/args/containerd-template.toml"
  run_with_sudo sed -i '/--log-level fatal/d' "${SNAP_DATA}/args/containerd"
  echo removing all existing data
  for i in $(cat "${SNAP_DATA}/args/zfs-volumes")
  do
    echo "destroying ZFS volume ${i}"
    run_with_sudo "${SNAP}/sbin/zfs" destroy -r "${i}"
  done
  run_with_sudo rm -rf "${SNAP_COMMON}/var/lib/containerd/*"

  run_with_sudo rm -f "${SNAP_DATA}/args/zfs-volumes"

  # add mount for default storage group
  #zfs create -o mountpoint=/var/snap/microk8s/common/default-storage tank/containerd

  echo "restarting microk8s"
  run_with_sudo preserve_env snapctl start "${SNAP_NAME}"
  echo "Waiting for microk8s to restart."
  "${SNAP}/microk8s-status.wrapper" --wait-ready >/dev/null
  echo "ZFS is disabled"
fi
