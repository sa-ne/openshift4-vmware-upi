# Automated Provisioning of OpenShift 4.5 on VMware

This repository contains a set of playbooks to help facilitate the deployment of OpenShift 4.5 on VMware.

## Background

This is a continuation of the [work](https://github.com/sa-ne/openshift4-rhv-upi) done for automating the deployment of OpenShift 4 on RHV. The goal is to automate the configuration of a helper node (web server for ignition artifacts, external LB and DHCP) and automatically deploy Red Hat CoreOS (RHCOS) nodes on VMware.

## Specific Automations

* Creation of all SRV, A and PTR records in IdM
* Deployment of an httpd server to host installation artifacts
* Deployment of HAProxy and applicable configuration
* Deployment of dhcpd and applicable fixed host entries (static assignment)
* Uploading RHCOS OVA template
* Deployment and configuration of RHCOS VMs on VMware
* Ordered starting of VMs

## Requirements

To leverage the automation in this guide you need to bring the following:

* VMware Environment (tested on ESXi/vSphere 7.0)
* IdM Server with DNS Enabled
 * Must have Proper Forward/Reverse Zones Configured
* RHEL 7 Server which will act as a Web Server, Load Balancer and DHCP Server
 * Only Repository Requirement is `rhel-7-server-rpms`
 
### Naming Convention

Bootstrap, master and worker hostnames must use the following format:

* bootstrap.\<base domain\>
* master0.\<base domain\>
* master1.\<base domain\>
* masterX.\<base domain\>
* worker0.\<base domain\>
* worker1.\<base domain\>
* workerX.\<base domain\>

The HA proxy installation on the helper node will load balance ingress to worker nodes. All other node types (for instance, if you add infra nodes) that do not have 'worker' in them will be provisioned last.

# Installing

Please read through the [Installing on vSphere](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.5/html-single/installing_on_vsphere/index#installing-vsphere) installation documentation before proceeding.

## Clone this Repository

Find a good working directory and clone this repository using the following command:

```console
$ git clone https://github.com/sa-ne/openshift4-vmware-upi.git
```

## Create DNS Zones in IdM

Login to your IdM server and make sure a reverse zone is configured for your subnet. My lab has a subnet of `172.16.10.0` so the corresponding reverse zone is called `10.16.172.in-addr.arpa.`. Make sure a forward zone is configured as well. It should be whatever is defined in the `<cluster_name>`.`<base_domain>` variables in your Ansible inventory file (`vmware-upi.ocp.pwc.umbrella.local` in this example).

## Creating Inventory File for Ansible

An example inventory file is included for Ansible (`inventory-example.yaml`). Use this file as a baseline. Make sure to configure the appropriate number of master/worker nodes for your deployment.

The following global variables will need to be modified (the default values are what I use in my lab, consider them examples):

|Variable|Description|
|:---|:---|
|ova\_path|Local path to the RHCOS OVA template|
|ova\_vm\_name|Name of the virtual machine that is created when uploading the OVA|
|base\_domain|The base DNS domain. Not to be confused with the base domain in the UPI instructions. Our base\_domain variable in this case is `<cluster_name>`.`<base_domain>`|
|cluster\_name|The name of our cluster (`vmware-upi` in the example)|
|dhcp\_server\_dns\_servers|DNS server assigned by DHCP server|
|dhcp\_server\_gateway|Gateway assigned by DHCP server|
|dhcp\_server\_subnet\_mask|Subnet mask assigned by DHCP server|
|dhcp\_server\_subnet|IP Subnet used to configure dhcpd.conf|
|load\_balancer\_ip|This IP address of your load balancer (the server that HAProxy will be installed on)|
|installation\_directory|Director containing the ignition files for our cluster|

Under the `helper` group include the FQDN for your helper node. Also make sure you configure the `httpd_port` variable and IP address.

For the individual node configuration, be sure to update the hosts in the `pg` hostgroup. Several parameters will need to be changed for _each_ host including `ip`, `memory`, etc. Match up your VMware environment with the inventory file.

## Creating an Ansible Vault

In the directory that contains your cloned copy of this git repo, create an Ansible vault called vault.yaml as follows:

```console
$ ansible-vault create vault.yaml
```

The vault requires the following variables. Adjust the values to suit your environment.

```yaml
---
vcenter_hostname: "vsphere.pwc.umbrella.local"
vcenter_username: "administrator@vsphere.local"
vcenter_password: "changeme"
vcenter_datacenter: "PWC"
vcenter_cluster: "Primary"
vcenter_datastore: "pool-nvme-vms"
vcenter_network: "Lab Network"
ipa_hostname: "idm1.umbrella.local"
ipa_username: "admin"
ipa_password: "changeme"
```

## Download the OpenShift Installer

The OpenShift Installer releases are stored [here](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/). Find the installer, right click on the "Download Now" button and select copy link. Then pull the installer using curl as shown (Linux client used as example):

```console
$ curl -o openshift-install-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz
```

Extract the archive and continue.

## Creating Ignition Configs

After you download the installer we need to create our ignition configs using the `openshift-install` command. Create a file called `install-config.yaml` similar to the one show below. This example shows 3 masters and 0 worker nodes. Since this is a UPI installation, we will 'manually' add worker nodes to the cluster.


```yaml
apiVersion: v1
baseDomain: ocp.pwc.umbrella.local
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 0
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: vmware-upi
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  vsphere:
    vcenter: vsphere.pwc.umbrella.local
    username: administrator@vsphere.local
    password: changeme
    datacenter: PWC
    defaultDatastore: pool-nvme-vms
    folder: /PWC/vms/vmware-upi
pullSecret: '{ ... }'
sshKey: 'ssh-rsa ... user@host'
```

You will need to modify vsphere, name, baseDomain, pullSecret and sshKey (be sure to use your _public_ key) with the appropriate values. Next, copy `install-config.yaml` into your working directory (`~/upi/vmware-upi` in this example).

Also note starting with OpenShift 4.4, the `folder` variable is now required for UPI based installations. This is not explicitly stated in the OpenShift installation instructions and a documentation bug was filed to correct that.

Your pull secret can be obtained from the [OpenShift start page](https://cloud.redhat.com/openshift/install/vsphere/user-provisioned).

Before we create the ignition configs we need to generate our manifests first.

```console
$ ./openshift-install create manifests --dir=~/upi/vmware-upi
```

Since we specified 0 worker nodes in the install-config.yaml file, the masters become schedulable. We want to prevent that, so run the following sed command to disable:

```console
$ sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' ~/upi/vmware-upi/manifests/cluster-scheduler-02-config.yml
```

Next, we want to disable the manifests that define the control plane machines:

```console
$ rm -f ~/upi/vmware-upi/openshift/99_openshift-cluster-api_master-machines-*.yaml
```

Last we want to disable the manifests that define the worker nodes:

```console
$ rm -f ~/upi/vmware-upi/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
```

With our manifests modified to support a UPI installation, run the OpenShift installer as follows to generate your ignition configs.

```console
$ ./openshift-install create ignition-configs --dir=~/upi/vmware-upi
```

## Staging OVA File

First we need to obtain the RHCOS OVA file. Place this in the same location referenced in the variable `ova_path` in your inventory file (`/tmp` in this example).

```console
$ curl -o /tmp/rhcos-4.5.2-x86_64-vmware.x86_64.ova https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.5/latest/rhcos-4.5.2-x86_64-vmware.x86_64.ova
```

This template will automatically get uploaded to VMware when the playbook runs.

## Deploying OpenShift 4.5 on VMware with Ansible

To kick off the installation, simply run the provision.yaml playbook as follows:

```console
$ ansible-playbook -i inventory.yaml --ask-vault-pass provision.yaml
```

The order of operations for the `provision.yaml` playbook is as follows:

* Create DNS Entries in IdM
* Create VMs in VMware
	- Create Appropriate Folder Structure
	- Upload OVA Template
	- Create Virtual Machines (cloned from OVA template)
* Configure Load Balancer Host
	- Install and Configure dhcpd
	- Install and Configure HAProxy
	- Install and Configure httpd
* Boot VMs
	- Start bootstrap VM and wait for SSH
	- Start master VMs and wait for SSH
	- Start worker VMs and wait for SSH
	- Start other VMs and wait for SSH
	
Once the playbook completes (should take several minutes) continue with the instructions.

### Skipping Portions of Automation

If you already have your own DNS, DHCP or Load Balancer you can skip those portions of the automation by passing the appropriate `--skip-tags` argument to the `ansible-playbook` command.

Each step of the automation is placed in its own role. Each is tagged `ipa`, `dhcpd` and `haproxy`. If you have your own DHCP configured, you can skip that portion as follows:

```console
$ ansible-playbook -i inventory.yaml --ask-vault-pass --skip-tags dhcpd provision.yaml
```

All three roles could be skipped using the following command:

```console
$ ansible-playbook -i inventory.yaml --ask-vault-pass --skip-tags dhcpd,ipa,haproxy provision.yaml
```

## Finishing the Deployment

Once the VMs boot RHCOS will be installed and nodes will automatically start configuring themselves. Before the worker nodes join the cluster you will need to approve two CSRs for each node.

Set your `KUBECONFIG` environment variable to the kubeconfig file generated in your installation directory, for example:

```console
$ export KUBECONFIG=~/upi/vmware-upi/auth/kubeconfig
```

Run the following to check for pending CSRs:

```console
$ oc get csr
```

Approve each pending CSR by hand, or approve all by running the following command:

```console
$ oc get csr | grep -i pending | awk '{ print $1 }' | xargs oc adm certificate approve
```

Once all CSRs are approved, run the following command to ensure the bootstrap process completes (be sure to adjust the `--dir` flag with your working directory):

```console
$ ./openshift-install --dir=~/upi/vmware-upi wait-for bootstrap-complete
INFO Waiting up to 30m0s for the Kubernetes API at https://api.vmware-upi.ocp.pwc.umbrella.local:6443... 
INFO API v1.13.4+f2cc675 up                       
INFO Waiting up to 30m0s for bootstrapping to complete... 
INFO It is now safe to remove the bootstrap resources
```

Once the initial openshift-install and ansible-playbook commands complete successfully, run the following playbook to remove the bootstrap node from the various backends in haproxy.

```console
$ ansible-playbook -i inventory.yaml bootstrap-cleanup.yaml
```

At this point the bootstrap node can be shutdown and discarded. To verify the installation completed successfully, run the following command:

```console
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.5.2     True        False         13h     Cluster version is 4.5.2
```

# Installing vSphere CSI Drivers

By default, OpenShift will create a storage class that leverages the in-tree vSphere volume plugin to handle dynamic volume provisioning. The CSI drivers promise a deeper integration with vSphere to handle dynamic volume provisioning.

The source for the driver can be found [here](https://github.com/kubernetes-sigs/vsphere-csi-driver) along with [specific installation instructions](https://cloud-provider-vsphere.sigs.k8s.io/tutorials/kubernetes-on-vsphere-with-kubeadm.html). The documentation references an installation against a very basic Kubernetes cluster so extensive modification is required to make this work with OpenShift.

## Background/Requirements

* According to the documentation, the out of tree CPI needs to be installed.
* vSphere 6.7U3+ is also required. Tested on vSphere 7.0.
* CPI and CSI components will be installed in the `vsphere` namespace for this example (upstream documentation deploys to `kube-system` namespace).

## Install vSphere Cloud Provider Interface

### Create Namespace for vSphere CPI and CSI

```
$ oc new-project vsphere
```

### Taint Worker Nodes

All worker nodes are required to have the `node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule` taint. This will be removed automatically once the vSphere CPI is installed.

```
$ oc adm taint node workerX.vmware-upi.ocp.pwc.umbrella.local node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule
```

### Create a CPI ConfigMap

This config file (see csi/cpi/vsphere.conf) contains details about our vSphere environment. Modify accordingly and create the ConfigMap resource as follows:

```
$ oc create configmap cloud-config --from-file=csi/cpi/vsphere.conf --namespace=vsphere
```

### Create CPI vSphere Secret

Create a secret (see csi/cpi/cpi-global-secret.yaml) that contains the appropriate login information for our vSphere endpoint. Modify accordingly and create the Secret resource as follows:

```
$ oc create -f csi/cpi/cpi-global-secret.yaml
```

### Create Roles/RoleBindings for vSphere CPI

Next we will create the appropriate RBAC controls for the CPI. These files were modified to place the resources in the `vsphere` namespace.

```
$ oc create -f csi/cpi/0-cloud-controller-manager-roles.yaml
```

```
$ oc create -f csi/cpi/1-cloud-controller-manager-role-bindings.yaml
```

Since we are not deploying to the `kube-system` namespace, an additional RoleBinding is needed for the `cloud-controller-manager` service account.

```
$ oc create rolebinding -n kube-system vsphere-cpi-kubesystem --role=extension-apiserver-authentication-reader --serviceaccount=vsphere:cloud-controller-manager
```

We also need to add the `privileged` SCC to the service account as these pods will require privileged access to the RHCOS container host.

```
$ oc adm policy add-scc-to-user privileged -z cloud-controller-manager
```

### Create CPI DaemonSet

Lastly, we need to create the CPI DaemonSet. This file was modified to place the resources in the `vsphere` namespace.

```
$ oc create -f csi/cpi/2-vsphere-cloud-controller-manager-ds.yaml
```

### Verify CPI Deployment

Verify the appropriate pods are deployed using the following command:

```
$ oc get pods -n vsphere --selector='k8s-app=vsphere-cloud-controller-manager'
NAME                                     READY   STATUS    RESTARTS   AGE
vsphere-cloud-controller-manager-drvss   1/1     Running   0          161m
vsphere-cloud-controller-manager-hjjkl   1/1     Running   0          161m
vsphere-cloud-controller-manager-nj2t6   1/1     Running   0          161m
```

## Install vSphere CSI Drivers

Now that the CPI is installed, we can install the vSphere CSI drivers.

### Create CSI vSphere Secret

Create a secret (see csi/csi/csi-vsphere.conf) that contains the appropriate login information for our vSphere endpoint. Modify accordingly and create the Secret resource as follows:

```
$ oc create secret generic vsphere-config-secret --from-file=csi/csi/csi-vsphere.conf --namespace=vsphere
```

### Create Roles/RoleBindings for vSphere CSI Driver

Next we will create the appropriate RBAC controls for the CSI drivers. These files were modified to place the resources in the `vsphere` namespace.

```
$ oc create -f csi/csi/0-vsphere-csi-controller-rbac.yaml
```

Since we are not deploying to the `kube-system` namespace, an additional RoleBinding is needed for the `vsphere-csi-controller` service account.

```
$ oc create rolebinding -n kube-system vsphere-csi-kubesystem --role=extension-apiserver-authentication-reader --serviceaccount=vsphere:vsphere-csi-controller
```

We also need to add the `privileged` SCC to the service account as these pods will require privileged access to the RHCOS container host.

```
$ oc adm policy add-scc-to-user privileged -z vsphere-csi-controller
```

### Creating the CSI Controller Deployment

Extensive modification was done to the StatefulSet set. The referenced kubelet path is different in OCP, so the following regex was run to adjust the appropriate paths:

```
%s/\/var\/lib\/csi\/sockets\/pluginproxy/\/var\/lib\/kubelet\/plugins_registry/g
```

The namespace was also changed to `vsphere`.

Create the CSI Controller StatefulSet as follows:

```
$ oc create -f csi/csi/1-vsphere-csi-controller-deployment.yaml
```

### Creating the CSI Driver DaemonSet

By default no service account is associated with the DaemonSet, so the `vsphere-csi-controller` was added to the template spec. The namespace was also updated to `vsphere`.

Create the CSI Driver DaemonSet as follows:

```
$ oc create -f csi/csi/2-vsphere-csi-node-ds.yaml
```

### Verify CSI Driver Deployment

Make sure the the CSI Driver controller is running as follows:

```
$ oc get pods -n vsphere --selector='app=vsphere-csi-controller'
NAME                       READY   STATUS    RESTARTS   AGE
vsphere-csi-controller-0   5/5     Running   0          147m
```

Also make sure the appropriate node pods are running as follows:

```
$ oc get pods --selector='app=vsphere-csi-node'
NAME                     READY   STATUS    RESTARTS   AGE
vsphere-csi-node-6cfsj   3/3     Running   0          130m
vsphere-csi-node-nsdsj   3/3     Running   0          130m
```

We can also validate the appropriate CRDs by running:

```
$ oc get csinode
NAME                                        CREATED AT
worker0.vmware-upi.ocp.pwc.umbrella.local   2020-01-29T16:18:02Z
worker1.vmware-upi.ocp.pwc.umbrella.local   2020-01-29T16:18:03Z
```

Also verify the driver has been properly assigned on each CSINode:

```
$ oc get csinode -ojson | jq '.items[].spec.drivers[] | .name, .nodeID'
"csi.vsphere.vmware.com"
"worker0.vmware-upi.ocp.pwc.umbrella.local"
"csi.vsphere.vmware.com"
"worker1.vmware-upi.ocp.pwc.umbrella.local"
```

## Creating a Storage Class

A very simple storage class is referenced in csi/csi/storageclass.yaml. Adjust the datastore URI accordingly and run:

```
$ oc create -f csi/csi/storageclass.yaml
```

You should see the storage class defined in the following:

```
$ oc get sc
NAME                                 PROVISIONER                    AGE
example-vanilla-block-sc (default)   csi.vsphere.vmware.com         72m
thin                                 kubernetes.io/vsphere-volume   19h
```


### Testing a PVC/POD

To create a simple PVC request, run the following:

```
$ oc create -n vsphere -f csi/csi/example-pvc.yaml
```

Validate the PVC was created:

```
$ oc get pvc -n vsphere example-vanilla-block-pvc
NAME                        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS               AGE
example-vanilla-block-pvc   Bound    pvc-f8e1db9b-4aea-4eb3-b8c0-8cf7a6ec7d7f   5Gi        RWO            example-vanilla-block-sc   73m
```

Next create a pod to bind to the new PVC:

```
$ oc create -n vsphere -f csi/csi/example-pod.yaml
```

Validate the pod was successfully created:

```
$ oc get pod -n vsphere example-vanilla-block-pod
NAME                        READY   STATUS    RESTARTS   AGE
example-vanilla-block-pod   1/1     Running   0          73m
```

# Install OpenShift Container Storage using vSphere CSI Drivers

The installation process for OCS is relatively straightforward. We will just substitute the default `thin` storage class that leverages the in-tree vSphere volume plugin with a new storage class (named `vsphere-csi` in this example) that is backed by the vSphere CSI drivers.

## Create vSphere CSI Storage Class

Run the following command to create the `vsphere-csi` storage class. Be sure to modify the URI in `datastoreurl` to match your environment.

```
$ oc create -f ocs/vsphere-csi-storageclass.yaml
```

Verify the storage class was created as follows:

```
$ oc get storageclass vsphere-csi
NAME          PROVISIONER              AGE
vsphere-csi   csi.vsphere.vmware.com   40m
```

## Label Nodes for OpenShift Container Storage

Before we begin an installation, we need to label our OCS nodes with the label `cluster.ocs.openshift.io/openshift-storage`. Label each node with the following command:

```console
$ oc label node workerX.vmware-upi.ocp.pwc.umbrella.local cluster.ocs.openshift.io/openshift-storage=''
```

## Deploying the OCS Operator

To deploy the OCS operator, run the following command:

```console
$ oc create -f ocs/ocs-operator.yaml
```

### Verifying Operator Deployment

To verify the operators were successfully installed, run the following:

```console
$ oc get csv -n openshift-storage
NAME                  DISPLAY                       VERSION   REPLACES              PHASE
awss3operator.1.0.1   AWS S3 Operator               1.0.1     awss3operator.1.0.0   Succeeded
ocs-operator.v4.2.1   OpenShift Container Storage   4.2.1                           Succeeded
```

You should see phase `Succeeded` for all operators.

## Provisioning OCS Cluster

Modify the file `ocs/storagecluster.yaml` and adjust the storage requests accordingly.

To create the cluster, run the following command:

```console
$ oc create -f ocs/storagecluster.yaml
```

The installation process should take approximately 5 minutes. Run `oc get pods -n openshift-storage -w` to observe the process.

To verify the installation is complete, run the following:

```console
$ oc get storagecluster storagecluster -ojson -n openshift-storage | jq .status
{
  "cephBlockPoolsCreated": true,
  "cephFilesystemsCreated": true,
  "cephObjectStoreUsersCreated": true,
  "cephObjectStoresCreated": true,
  ...
}
```

All fields should be marked true.

## Adding Storage for OpenShift Registry

OCS provides RBD and CephFS backed storage classes for use within the cluster. We can leverage the CephFS storage class to create a PVC for the OpenShift registry.

Modify the file `ocs/registry-cephfs-pvc.yaml` file and adjust the size of the claim. Then run the following to create the PVC:

```console
$ oc create -f ocs/registry-cephfs-pvc.yaml
```

To reconfigure the registry to use our new PVC, run the following:

```console
$ oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"managementState":"Managed","storage":{"pvc":{"claim":"registry"}}}}'
```

# Retiring

Playbooks are also provided to remove VMs from VMware and DNS entries from IdM. To do this, run the retirement playbook as follows:

```console
$ ansible-playbook -i inventory.yaml --ask-vault-pass retire.yaml
```

