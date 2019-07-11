# Automated Provisioning of OpenShift 4.1 on VMware

This repository contains a set of playbooks to help facilitate the deployment of OpenShift 4.1 on VMware.

## Background

This is a continuation of the [work](https://github.com/sa-ne/openshift4-rhv-upi) done for automating the deployment of OpenShift 4.1 on RHV. The goal is to automate the configuration of a helper node/load balancer and automatically deploy Red Hat CoreOS (RHCOS) nodes on VMware. Upon completion your cluster should be at the _bootstrap complete_ phase.

## Specific Automations

* Creation of all SRV, A and PTR records in IdM
* Deployment of an httpd server to host installation artifacts
* Deployment of HAProxy and applicable configuration
* Deployment of dhcpd and applicable fixed host entries (static assignment)
* Uploading RHCOS OVA template
* Deployment and configuration of RHCOS VMs on VMware
* Ordered starting (i.e. installation) of VMs

## Requirements

To leverage the automation in this guide you need to bring the following:

* VMware Environment (tested on ESXi/vSphere 6.7)
* IdM Server with DNS Enabled
 * Must have Proper Forward/Reverse Zones Configured
* RHEL 7 Server which will act as a Web Server, Load Balancer and DHCP Server
 * Only Repository Requirement is `rhel-7-server-rpms`
 
### Naming Convention

All hostnames must use the following format:

* bootstrap.\<base domain\>
* master0.\<base domain\>
* master1.\<base domain\>
* masterX.\<base domain\>
* worker0.\<base domain\>
* worker1.\<base domain\>
* workerX.\<base domain\>

## Noted VMware UPI Installation Issues

* The RHCOS OVA has `ddb.virtualHWVersion = "6"`. This will cause issues in later versions of VMware.
* Installation documents call for the `Latency Sensitivity` parameter to be set to `High` on each VM. This second order effect of this setting is that CPU/Memory allocation must be reserved up front, potentially limiting deployment options on smaller clusters.

# Installing

Read through the [Installing on vSphere](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.1/html-single/installing/index#installing-on-vsphere) installation documentation before proceeding.

## Clone this Repository

Find a good working directory and clone this repository using the following command:

```console
$ git clone https://github.com/sa-ne/openshift4-vmware-upi.git
```

## Create DNS Zones in IdM

Login to your IdM server and make sure a reverse zone is configured for your subnet. My lab has a subnet of `172.16.10.0` so the corresponding reverse zone is called `10.16.172.in-addr.arpa.`. Make sure a forward zone is configured as well. It should be whatever is defined in the `base_domain` variable in your Ansible inventory file (`vmware-upi.ocp.pwc.umbrella.local` in this example).

## Creating Inventory File for Ansible

An example inventory file is included for Ansible (`inventory-example.yml`). Use this file as a baseline. Make sure to configure the appropriate number of master/worker nodes for your deployment.

The following global variables will need to be modified (the default values are what I use in my lab, consider them examples):

|Variable|Description|
|:---|:---|
|ova\_path|Local path to the RHCOS OVA template|
|ova\_vm\_name|Name of the virtual machine that is created when uploading the OVA|
|base\_domain|The base DNS domain. Not to be confused with the base domain in the UPI instructions. Our base\_domain variable in this case is `<cluster_name>`.`<base_domain>`|
|dhcp\_server\_dns\_servers|DNS server assigned by DHCP server|
|dhcp\_server\_gateway|Gateway assigned by DHCP server|
|dhcp\_server\_subnet\_mask|Subnet mask assigned by DHCP server|
|dhcp\_server\_subnet|IP Subnet used to configure dhcpd.conf|
|load\_balancer\_ip|This IP address of your load balancer (the server that HAProxy will be installed on)|

Under the `webserver` and `loadbalancer` group include the FQDN of each host. Also make sure you configure the `httpd_port` variable for the web server host. In this example, the web server that will serve up installation artifacts and load balancer (HAProxy) are the same host.

For the individual node configuration, be sure to update the hosts in the `pg` hostgroup. Several parameters will need to be changed for _each_ host including `ip`, `memory`, `cores` and `cpu_reservation`. Match up your VMware environment with the inventory file.

Since we set `Latency Sensitivity` to `High` on each virtual machine, memory and CPU resources are allocated up front. `cpu_reservation` can be calculated as follows:

1. Find the CPU model (Xeon X5675) and determine GHz (3.06GHz)
2. Find the number of cores assigned to VM (2)
2. 3.06GHz * (1000MHz/GHz) * 2 = 6120

## Creating an Ansible Vault

In the directory that contains your cloned copy of this git repo, create an Ansible vault called vault.yml as follows:

```console
$ ansible-vault create vault.yml
```

The vault requires the following variables. Adjust the values to suit your environment.

```yaml
---
vcenter_hostname: "vsphere.pwc.umbrella.local"
vcenter_username: "administrator@vsphere.local"
vcenter_password: "changeme"
vcenter_datacenter: "Datacenter"
vcenter_cluster: "PWC"
vcenter_datastore: "vmware-datastore"
vcenter_network: "VM Network"
ipa_hostname: "idm1.umbrella.local"
ipa_username: "admin"
ipa_password: "changeme"
```

## Download the OpenShift Installer

The OpenShift Installer releases are stored [here](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/). Find the installer, right click on the "Download Now" button and select copy link. Then pull the installer using curl (be sure to quote the URL) as shown (linux client used as example):

```console
$ curl -o openshift-install-linux-4.1.4.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux-4.1.4.tar.gz
```

Extract the archive and continue.

## Creating Ignition Configs

After you download the installer we need to create our ignition configs using the `openshift-install` command. Create a file called `install-config.yaml` similar to the one show below. This example shows 3 masters and 2 worker nodes.

```yaml
apiVersion: v1
baseDomain: ocp.pwc.umbrella.local
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 1
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
    datacenter: Datacenter
    defaultDatastore: vmware-datastore
pullSecret: '{ ... }'
sshKey: 'ssh-rsa ... user@host'
```

You will need to modify vsphere, baseDomain, pullSecret and sshKey (be sure to use your _public_ key) with the appropriate values. Next, copy `install-config.yaml` into your working directory (`/home/chris/upi/vmware-upi` in this example) and run the OpenShift installer as follows to generate your Ignition configs.

Your pull secret can be obtained from the [OpenShift start page](https://cloud.redhat.com/openshift/install/metal/user-provisioned).

```console
$ ./openshift-installer create ignition-configs --dir=/home/chris/upi/vmware-upi
```

## Staging Content

First we need to obtain the RHCOS OVA template. Place this in the same location referenced in the variable `ova\_path` in your inventory file (`/tmp` in this example).

```console
$ curl -o /tmp/rhcos-4.1.0-x86_64-vmware.ova https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/latest/rhcos-4.1.0-x86_64-vmware.ova
```

This template will automatically get uploaded to VMware when the playbook runs.

Next we need to stage the bootstrap scripts. Bootstrap content is injected into the OVA via base64 encoded vApp properties. Unfortunately the bootstrap ignition files is too large, so we will need to create a stub that pulls the primary ignition config from our webserver. To do this, create the `append-bootstrap.ign` config file in your staging directory (`/home/chris/upi/vmware-upi` in this example). Make sure `source` points to your web server.

```json
{
  "ignition": {
    "config": {
      "append": [
        {
          "source": "http://lb.vmware-upi.ocp.pwc.umbrella.local:8080/bootstrap.ign",
          "verification": {}
        }
      ]
    },
    "timeouts": {},
    "version": "2.1.0"
  },
  "networkd": {},
  "passwd": {},
  "storage": {},
  "systemd": {}
}
```

Once `append-bootstrap.ign` is created, we need to insert the base64 encoded values of `append-bootstrap.ign`, `master.ign` and `worker.ign` in the file base64.yml. To do this for `append-bootstrap.ign` run the following command:

```console
$ base64 -w0 /home/chris/upi/vmware-upi/append-bootstrap.ign
```

Assign the output of that command to the variable `base64_bootstrap`. Repeat the process for `master.ign` and `worker.ign` with the output going into `base64_master` and `base64_worker` variables, respectively.

Lastly, copy `bootstrap.ign` to the document root of your web server (make sure the directory `/var/www/html` exists first).

_NOTE: You may be wondering about SELinux contexts since httpd is not installed. Fear not, our playbooks will handle that during the installation phase._

```console
$ scp /home/chris/upi/vmware-upi/bootstrap.ign root@lb.vmware-upi.ocp.pwc.umbrella.local:/var/www/html/
```

## Deploying OpenShift 4.1 on VMware with Ansible

To kick off the installation, simply run the provision.yml playbook as follows:

```console
$ ansible-playbook -e @base64.yml -i inventory.yml --ask-vault-pass provision.yml
```

The order of operations for the `provision.yml` playbook is as follows:

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
	
Once the playbook completes (should several minutes) continue with the instructions.

### Skipping Portions of Automation

If you already have your own DNS, DHCP or Load Balancer you can skip those portions of the automation by passing the appropriate `--skip-tags` argument to the `ansible-playbook` command.

Each step of the automation is placed in its own role. Each is tagged ipa, dhcpd and haproxy. If you have your own DHCP configured, you can skip that portion as follows:

```console
$ ansible-playbook -e @base64.yml -i inventory.yml --ask-vault-pass --skip-tags dhcpd provision.yml
```

All three roles could be skipped using the following command:

```console
$ ansible-playbook -e @base64.yml -i inventory.yml --ask-vault-pass --skip-tags dhcpd,ipa,haproxy provision.yml
```

## Finishing the Deployment

Once the VMs boot RHCOS will be installed and nodes will automatically start configuring themselves. From this point we are essentially following the rest of the VMware UPI instructions starting with [Creating the Cluster](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.1/html-single/installing/index#installation-installing-bare-metal_installing-vsphere).

Run the following command to ensure the bootstrap process completes (be sure to adjust the `--dir` flag with your working directory):

```console
$ ./openshift-install --dir=/home/chris/upi/vmware-upi wait-for bootstrap-complete
INFO Waiting up to 30m0s for the Kubernetes API at https://api.vmware-upi.ocp.pwc.umbrella.local:6443... 
INFO API v1.13.4+f2cc675 up                       
INFO Waiting up to 30m0s for bootstrapping to complete... 
INFO It is now safe to remove the bootstrap resources
```

Once this openshift-install command completes successfully, login to the load balancer and comment out the references to the bootstrap server in `/etc/haproxy/haproxy.cfg`. There should be two references, one in the backend configuration `backend_22623` and one in the backend configuration `backend_6443`.

Lastly, refer to the VMware UPI documentation and complete [Logging into the cluster](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.1/html-single/installing/index#cli-logging-in-kubeadmin_installing-vsphere) and all remaining steps.

# Retiring

Playbooks are also provided to remove VMs from VMware and DNS entries from IdM. To do this, run the retirement playbook as follows:

```console
$ ansible-playbook -i inventory.yml --ask-vault-pass retire.yml
```