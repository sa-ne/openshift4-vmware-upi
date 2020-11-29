#!/bin/bash
oc get csr -ojson | jq -r '.items[] | select(.status=={}) | .metadata.name' | xargs oc adm certificate approve