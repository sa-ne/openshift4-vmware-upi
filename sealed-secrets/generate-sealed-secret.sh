#!/bin/bash

if [ "$#" -ne 2 ] ;
then
	echo -e "Usage:\n$0 <scope> <secret yaml file>"
	exit
fi

case $1 in
	strict)
    	;;
	namespace-wide)
		;;
	cluster-wide)
		;;
	*)
		echo "<scope> must be set to strict, namespace-wide or cluster-wide!"
		exit
		;;
esac

if [ ! -f "$2" ] ;
then
	echo "Could not find the file $1"
	exit
fi

source variables.sh

kubeseal -o yaml --cert "${PUBLICKEY}" --scope $1 < $2

