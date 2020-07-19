#!/bin/bash

# Use this script to verify DNS entires for your OpenShift 4 cluster.
# Checks for API end points, app wildcard, A/PTR records for nodes
# and SRV/A for etcd. Be sure to adjust CLUSTER_NAME and BASE_DOMAIN
# accordingly, as well as the NODES array to match your environment.
#
# $? returns 0 on success and 1 on failure.

CLUSTER_NAME=rhv-upi
BASE_DOMAIN=ocp.pwc.umbrella.local
DIG=/usr/bin/dig

NODES=(bootstrap master0 master1 master2 worker0 worker1 worker2 worker3 worker4 worker5)
API=(api api-int)
ETCD=(etcd-0 etcd-1 etcd-2)

if [ ! -f $DIG ]; then
  echo "Could not find $DIG. Please ensure the bind-utils package is installed, or update the DIG variable to reflect the appropriate binary path."
  exit 1
fi

echo -e "Verifying node A/PTR records..."

for i in ${NODES[@]}
do
  RET=`$DIG A $i.$CLUSTER_NAME.$BASE_DOMAIN +short`

  if [ -z "$RET" ]; then
    echo "Could not resolve $i.$CLUSTER_NAME.$BASE_DOMAIN!"
    exit 1
  else
    echo "$i.$CLUSTER_NAME.$BASE_DOMAIN resolved to: $RET"

    PRET=`$DIG -x $RET +short`

    if [ -z "$PRET" ]; then
      echo "Could not resolve PTR record for $RET"
      exit 1
    else
      echo "PTR: $PRET"
    fi
  fi
done

echo -e "\nVerifying API A records..."

for i in ${API[@]}
do
  RET=`$DIG A $i.$CLUSTER_NAME.$BASE_DOMAIN +short`

  if [ -z "$RET" ]; then
    echo "Could not resolve $i.$CLUSTER_NAME.$BASE_DOMAIN!"
    exit 1
  else
    echo "$i.$CLUSTER_NAME.$BASE_DOMAIN resolved to: $RET"
  fi
done

echo -e "\nVerifying etcd A records..."

for i in ${ETCD[@]}
do                 
  RET=`$DIG A $i.$CLUSTER_NAME.$BASE_DOMAIN +short`
 
  if [ -z "$RET" ]; then
    echo "Could not resolve $i.$CLUSTER_NAME.$BASE_DOMAIN!"
    exit 1         
  else             
    echo "$i.$CLUSTER_NAME.$BASE_DOMAIN resolved to: $RET"
  fi               
done

echo -e "\nVerifying etcd SRV record..."

RET=`$DIG SRV _etcd-server-ssl._tcp.$CLUSTER_NAME.$BASE_DOMAIN +short`

if [ -z "$RET" ]; then
  echo "Could not resolve _etcd-server-ssl._tcp.$CLUSTER_NAME.$BASE_DOMAIN"
  exit 1
else
  echo -e "_etcd-server-ssl._tcp.$CLUSTER_NAME.$BASE_DOMAIN resolved to:\n$RET"
fi

echo -e "\nVerifying application wildcard A record..."

RET=`$DIG A *.apps.$CLUSTER_NAME.$BASE_DOMAIN +short`

if [ -z "$RET" ]; then
  echo "Could not resolve *.apps.$CLUSTER_NAME.$BASE_DOMAIN"
  exit 1
else
  echo "*.apps.$CLUSTER_NAME.$BASE_DOMAIN resolved to: $RET"
fi

echo -e "\nVerification succeeded!"
exit 0
