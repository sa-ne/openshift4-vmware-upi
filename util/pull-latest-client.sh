#!/bin/bash

MIRROR_PATH=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest

INST_TARBALL=openshift-install-linux.tar.gz
CLNT_TARBALL=openshift-client-linux.tar.gz

BIN_PATH=~/bin

curl -o $BIN_PATH/$INST_TARBALL $MIRROR_PATH/$INST_TARBALL
curl -o $BIN_PATH/$CLNT_TARBALL $MIRROR_PATH/$CLNT_TARBALL

tar -C $BIN_PATH -xvf $BIN_PATH/$INST_TARBALL openshift-install
tar -C $BIN_PATH -xvf $BIN_PATH/$CLNT_TARBALL oc kubectl

rm $BIN_PATH/$INST_TARBALL
rm $BIN_PATH/$CLNT_TARBALL
