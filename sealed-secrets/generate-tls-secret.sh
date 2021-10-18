#!/bin/bash

if [ ! -f "variables.sh" ] ;
then
	echo "Can't find variables file variables.sh!"
	exit
fi

if [ "$#" -ne 4 ] ;
then
	echo -e "Usage:\n$0 <name> <namespace> <crt> <key>"
	exit
fi

if [ ! -f "$3" ] ;
then
	echo "Could not find crt file $3..."
	exit
fi

if [ ! -f "$4" ] ;
then
	echo "Could not find key file $4..."
	exit
fi

oc create secret tls $1 -n $2 --cert=$3 --key=$4 -oyaml --dry-run=client

