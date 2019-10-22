Use Case Description: BeoStack Cluster
==============================

Use Case Definition
-------------------

#### Primary Actor
        Ops Admin
#### Goal in Context
        Create a large OpenStack Cluster consisting of a maximum number of different commodity hardware components.
#### Scope
        System
#### Level
        Summary
#### Stakeholders and Interests
* Business:
 ** cover peak workload with otherwise idle hardware
 ** allow non-destrictive, temporary integration of hardware
 ** allow utilization of existing GPU power in decentral workstations
 ** use minimal budget
* Security: service availability, data integrity and other security topics may be ignored
* Operations:
  * deployment needs to be fully automated
  * simple classification of different hardware types
  * easy to scale up and down
* Application Owner:
   * Self Service Compute, Storage and Network Ressources
   * Elastic Scalable
   * Tenant Isolation 
#### Precondition
* Existing Network Infrastructure
	* something like a 24 port VLAN enabled switch
	* two NICs per node, possibly using an external USB interface
	* DNS, NTP, optional CA  (IPA)
* Some Dedicated Storage
 * at least one whole drive needs to be available for OpenStack
 * harddrive requirements may be fulfilled by an external USB 3.1 Flash Drive
 * at least three nodes need to have two dedicated harddrives
#### Minimal Guarantees
#### Success Guarantees
#### Trigger
#### Main Success Scenario
#### Extensions
#### Technology & Data Variations List


Preparation1: IPA, Satellite and Director Hosts
-------------------------------
As basic network infrastructure components, RHEL IPA and Red Hat Satellite come in handy.
In case these services do not exist yet, the provided Kickstart examples [ipa-ks.cfg](/Kickstart/ipa-ks.cfg) and [Kickstart/sat65-ks.cfg](/Kickstart/sat65-ks.cfg) help to set up these services from scratch.
You will exchange the authorization credentials and the Activation Key with your own, and you probably need to adjust the network settings to fit your environment.

The IPA server can be used as CA to sign external SSL certifiates for the OpenStack cloud.

The Director instance may be running as a virtual machine somewhere. In fact, it is quite useful to do so, because such an VM can be snapshotted and easily recovered in case something breaks using commands like this:

```
[root@ipa images]# mv RHOS-D13.qcow2 RHOS-D13-base.qcow2; qemu-img create -f qcow2 -F qcow2 -b RHOS-D13-base.qcow2 RHOS-D13.qcow2
[root@ipa images]# rm -f RHOS-D13.qcow2; qemu-img create -f qcow2 -F qcow2 -b RHOS-D13-base.qcow2 RHOS-D13.qcow2
[root@ipa images]# 
```

To deploy the Director as a simple KVM instance, the provided [KVM-Director-13-install.sh](/KVM-Director-13-install.sh)
script encapsulate the virt-install together with the appropriate Kickstart file for the libvirt deployment.
You will exchange the authorization credentials and the Activation Key with your own, and you probably need to adjust the network settings to fit your environment.

After the Kickstart installation has finished, you may want to register the director in the IPA Realm created above. You also may want to install cockpit and verify that IPA is correctly signing CSRs for the director.

```
[root@director ~]# ipa-client install
[root@director ~]# yum -y install cockpit
[root@director ~]# firewall-cmd --add-service=cockpit --permanent
[root@director ~]# systemctl enable cockpit.socket
[root@director ~]# CERT_FILE=/etc/pki/tls/certs/$(hostname).pem
[root@director ~]# KEY_FILE=/etc/pki/tls/private/$(hostname).key
[root@director ~]# REALM=$(hostname -d|tr '[:lower:]' '[:upper:]');
[root@director ~]# ipa-getcert request -f ${CERT_FILE} -k ${KEY_FILE} -D $(hostname --fqdn) -C "sed -n w/etc/cockpit/ws-certs.d/50-from-certmonger.cert ${CERT_FILE} ${KEY_FILE}" -K HTTP/$(hostname --fqdn)@${REALM}
[root@director ~]# ipa-getcert list
[root@director ~]# 
```

Hardware Considerations
-----------------------

The purpose of this project is to integrate as many nodes into the cluster as possible. We may even want to include desktop hosts that are sitting unused over night and over the weekends to maximize the ressource power of our cluster.

In order to achieve this goal, we make two key design decisions for our BeoStack Cluster:
1. We use an cheap USB NIC to provide a second Ethernet interface for each node. This allows most desktop or laptop PCs to participate in the cluster. Such an interface is available at littel over €10 per piece.
2. We use an USB 3.1 Flash Drive as additional harddisk. This allows to deploy the OpenStack Overcloud even on nodes that need to keep their harddisk untouched for the regular day to day work. In addition, such Flash Drive devices allow to build a powerful Hyperconverged Infrastructure with nodes that have only one internal harddisk which can be used for the OpenStack Overcloud installation, but lack the ability to host a second harddisk for Ceph. The USB Flash Drive easily extends that setup and allows a cluster with many such devices to provide a substantial amount of storage for the cluster.


Implementation Part 1: Undercloud Installation
--------------------------------------------

The actual installation of the Undercloud requires the [undercloud.conf](templates/undercloud.conf) file to be present in the `/home/stack` directory.
You probably want to copy the whole [templates](/templates) directory to that location.

Check all the settings in the undercloud.conf for validity in your environment and make changes as appropriate.
To use IPA as externa CA, you need to create the `haproxy/director..@REALM` Services Principal in your IPA server.

Double-check you have your public IP set as alias on the physical interface of the provisioning network
```
2: eth0:
   inet 192.168.24.2/24 brd 192.168.24.255 scope global eth0:1
```

For the purpose of a BeoStack Cluster, we want to make use of all available hardware. In particular, we want to include hosts that do not provide any management interface like IPMI.
OpenStack supports this type of hardware with a so called `fake` driver. However, even though the documentation for OpenStack-13 directs otherwise, we need to set
```
enabled_hardware_types = ipmi,manual-management
```
using `manual-management` as in OpenStack-14.

We also leave `enabled_drivers` unset at this time.

If everything is set according to your local environment, the undercloud installation may start

```
[stack@director ~]$ openstack undercloud install
```

#### Enabling the fake_pxe Driver

Only after the installation is finished, we change the `enabled_drivers` settings in `/etc/ironic/ironic.conf` to enable the fake drivers [Blog](https://blog.headup.ws/node/45).


```
[root@director ~]# sed -i 's/#enabled_drivers =.*/enabled_drivers=pxe_ipmitool,fake,fake_pxe/' /etc/ironic/ironic.conf
[root@director ~]# systemctl restart openstack-ironic-conductor
[root@director ~]# 


(undercloud) [stack@director ~]$ openstack baremetal driver list
+---------------------+----------------------------+
| Supported driver(s) | Active host(s)             |
+---------------------+----------------------------+
| fake                | director.bxlab.lunetix.org |
| fake_pxe            | director.bxlab.lunetix.org |
| ipmi                | director.bxlab.lunetix.org |
| manual-management   | director.bxlab.lunetix.org |
| pxe_ipmitool        | director.bxlab.lunetix.org |
+---------------------+----------------------------+
(undercloud) [stack@director ~]$
```

The difference between `fake` and `fake_pxe` is that the former expects the node to be running on a pre-provisioned image while the latter uses PXE to deploy the network based image from scratch.


#### Fixing the ASIX AX88179 USB Network Driver

In order to perpare for the overcloud deployment we need to install the deployment images.
In addition we install the `libguestfs-tools` to customize these images before uploading them.
Setting the root password may be useful later on for debugging.
Exchanging the ax88179_178a driver for the ASIX AX88179 USB Ethernet adapter is actually a hard requirement because the driver provided with RHEL has a bug with MTU handling on VLAN networks at least with some switches [Blog](https://www.dynatrace.com/news/blog/openstack-network-mystery-2-bytes-cost-me-two-days-of-trouble/).

```
[stack@director ~]$ 
[stack@director ~]$ source ~/stackrc
(undercloud) [stack@director ~]$ sudo yum -y install rhosp-director-images rhosp-director-images-ipa libguestfs-tools
(undercloud) [stack@director ~]$ cd ~/images
(undercloud) [stack@director ~]$ for i in /usr/share/rhosp-director-images/overcloud-full-latest-13.0.tar /usr/share/rhosp-director-images/ironic-python-agent-latest-13.0.tar; do tar -xvf $i; done
(undercloud) [stack@director ~]$ virt-customize -a overcloud-full.qcow2 --root-password password:Geheim
(undercloud) [stack@director ~]$ virt-customize -a overcloud-full.qcow2 --copy-in ax88179_178a.ko.xz:/lib/modules/3.10.0-1062.1.2.el7.x86_64/kernel/drivers/net/usb/
(undercloud) [stack@director ~]$ openstack overcloud image upload --image-path /home/stack/images/
(undercloud) [stack@director ~]$ openstack subnet set --dns-nameserver 192.168.24.254 ctlplane-subnet

```

These steps conclude the installation of the Undercloud, next is the deployment of the Ocercloud.


Implementation Part 2: Overcloud Deployment
-------------------------------------------

#### Introspection

The installation of the overcloud starts with registering the nodes for introspection.

```
"nodes": [
     {
      "pm_type": "fake_pxe",
      "mac": [
        "74:d4:35:4e:39:9c"
      ],
      "name": "bx-controller",
      "cpu": "4",
      "memory": "16384",
      "disk": "1000",
      "arch": "x86_64",
      "capabilities": "node:control-0,profile:control,boot_option:local"
    }   ]
}
```

We use the `fake_pxe` driver for nodes that are not equipped with an IPMI interface or more sophisticated management boards. This leaves us with the duty to power the machines on and off as OpenStack Undecloud Installer requires.

```
(undercloud) [stack@director ~]$ openstack overcloud node import ~/instackenv.json
(undercloud) [stack@director ~]$ openstack overcloud node introspect --all-manageable --provide


(undercloud) [stack@director ~]$ watch -n 10 openstack baremetal node list
```

It is helpful to have a second terminal window open and watch the `openstack baremetal node list` for all power cycle requirements.
The introspection is a two stage process that requires the systems to power up and PXE boot once for the registration and then power cycle for a cleanup procedure. After cleanup has finished the nodes are in a `power off | available` state.




Network Setup

network name | cidr            | VLAN | defroute      | DNS           | fixed IPs       | DHCP range    | Pool  | Extra    
-------------|-----------------|------|---------------|---------------|-----------------|---------------|-------|------
external     | 192.168.1.0/24  | 100 | 192.168.1.254  | 192.168.1.254 | 5               |               |       |
ctlplane     | 192.168.24.0/24 | 1   | 192.168.24.254 | 192.168.122.1 | local: 1 public: 2 admin: 3 fixed: 5 | instance: 10-34 inspect: 100-120 | 35-69 | EC2: 192.168.24.2
tenant       | 10.150.0.0/16   | 200 |                |               | 0.5             | 0.10-0.34     | 0.35-0.69 |
storage      | 172.16.1.0/24   | 201 |                |               | 5               | 10-34         |35-69 |
internal_api | 172.16.2.0/24   | 202 |                | | 5         | 10-34      | 35-69 |
storage_mgmt | 172.16.3.0/24   | 203 | | | 5         | 10-34      | 35-69 |
management   | 172.16.4.0/24   | 204 | | | 5         | 10-34      | 35-69 |









Validation
---------------------

