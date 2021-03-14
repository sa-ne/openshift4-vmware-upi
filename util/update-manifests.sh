#!/bin/bash

if [[ ! -n $1 ]] ; then
    echo -e "Usage:\n$0 /path/to/manifests"
    exit 1
fi

if [[ ! -d $1/manifests || ! -d $1/openshift ]] ; then
    echo "Can't find the directories $1/manifests or $1/openshift!"
    exit 1
fi

echo "sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' $1/manifests/cluster-scheduler-02-config.yml"
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' $1/manifests/cluster-scheduler-02-config.yml

echo "rm -f $1/openshift/99_openshift-cluster-api_master-machines-*.yaml"
rm -f $1/openshift/99_openshift-cluster-api_master-machines-*.yaml

echo "rm -f $1/openshift/99_openshift-cluster-api_worker-machineset-*.yaml"
rm -f $1/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
