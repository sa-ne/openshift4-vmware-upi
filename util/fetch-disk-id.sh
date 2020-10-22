#!/bin/bash

OCS_NODES=(ocs-node0 ocs-node1 ocs-node2)
DNS_SUFFIX=vmware-upi.ocp.pwc.umbrella.local
OSD_SIZE=800G

for i in ${OCS_NODES[@]}
do
	DEVICE=`ssh core@$i.$DNS_SUFFIX "lsblk" | grep $OSD_SIZE | awk '{ print $1 }'`
	ID=`ssh core@$i.$DNS_SUFFIX "ls -la /dev/disk/by-id 2>&1 | grep -i vmware | grep $DEVICE"`

	echo -n "/dev/disk/by-id/"
	echo $ID | awk '{ print $9 }'
done
