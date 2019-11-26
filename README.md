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
  * cover peak workload with otherwise idle hardware
  * allow non-destrictive, temporary integration of hardware
  * allow utilization of existing GPU power in decentral workstations
  * use minimal budget
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


Rationale
---------

Back in the days, we have built huge HPC clusters using inexpensive PC hardware modeled after the [Beowulf Cluster](https://en.wikipedia.org/wiki/Beowulf_cluster) built by Thomas Sterling and Donald Becker at NASA.

In December 1998, we have built a huge Beowulf Cluster named [CLOWN](https://www.heise.de/ix/artikel/Manege-frei-505610.html) with more than 500 nodes.

While this is more than 20 years ago, the basic idea is still valid. The [CERN](https://superuser.openstack.org/articles/openstack-production-cern-lightning-talk/) research organization glues hundreds of nodes from participating organizations with 170 datacenters into their OpenStack compute grid.

So why not raise the Beowulf approach to the OpenStack level. AI for example is one  


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


#### Fixing the ASIX AX88179 and Realtec R8152 USB Network Driver

In order to perpare for the overcloud deployment we need to install the deployment images.
In addition we install the `libguestfs-tools` to customize these images before uploading them.
Setting the root password may be useful later on for debugging.

Exchanging the ax88179_178a driver for the ASIX AX88179 USB Ethernet adapter is actually a hard requirement because the driver provided with RHEL has a bug with MTU handling on VLAN networks at least with some switches [Blog](https://www.dynatrace.com/news/blog/openstack-network-mystery-2-bytes-cost-me-two-days-of-trouble/).

The Realtec R8152 apparently has some stability issues with the driver provided with OpenStack-13 which lead to USB bus reset and loss of the associated bridge devices. The newest driver does not have these issues.

Both divers need to be compiled for RHEL-7. Some minor patches like renaming '.ndo_change_mtu' to '.ndo_change_mtu_rh74' may be required.

In order to establish a smooth deployment workflow, it is necessary to replace the initramfs in the 'overcloud-full.qcow2' image with one containing the updated USB network drivers.

```
[stack@director ~]$ 
[stack@director ~]$ source ~/stackrc
(undercloud) [stack@director ~]$ sudo yum -y install rhosp-director-images rhosp-director-images-ipa libguestfs-tools
(undercloud) [stack@director ~]$ cd ~/images
(undercloud) [stack@director ~]$ for i in /usr/share/rhosp-director-images/overcloud-full-latest-13.0.tar /usr/share/rhosp-director-images/ironic-python-agent-latest-13.0.tar; do tar -xvf $i; done
(undercloud) [stack@director ~]$ virt-customize -a overcloud-full.qcow2 --root-password password:Geheim
(undercloud) [stack@director ~]$ virt-customize -a overcloud-full.qcow2 --copy-in ax88179_178a.ko.xz:/lib/modules/3.10.0-1062.4.1.el7.x86_64/kernel/drivers/net/usb/
(undercloud) [stack@director ~]$ virt-customize -a overcloud-full.qcow2 --copy-in r8152.ko.xz:/lib/modules/3.10.0-1062.4.1.el7.x86_64/kernel/drivers/net/usb/
(undercloud) [stack@director ~]$ virt-customize -a overcloud-full.qcow2 --copy-in initramfs-3.10.0-1062.4.1.el7.x86_64.img:/boot
(undercloud) [stack@director ~]$ openstack overcloud image upload --image-path /home/stack/images/
(undercloud) [stack@director ~]$ openstack subnet set --dns-nameserver 192.168.24.254 ctlplane-subnet

```

These steps conclude the installation of the Undercloud, next is the deployment of the Overcloud.


Implementation Part 2: Overcloud Deployment
-------------------------------------------

The Beostack Overcloud Cluster shall consist of three types of nodes:
* Controller (1 or 3 nodes),
* at least three dedicated hyperconverged ComputeHCI nodes with at least one internal SSD that will be integrated into one Ceph cluster and
* an arbitrary number of Compute nodes which provide CPU and RAM for the cluster.

In order to allow integration of such nodes in an OpenShift-4.2 IPI cluster running on top of these nodes, the nodes must have at least 16GB of RAM. Four nodes with 24GB or more are required for the Master and Boostrap nodes.


The ComputeHCI role does not have a predefined flavor associated, so we create one:

```
(undercloud) [stack@director ~]$ openstack overcloud roles generate -o templates/roles_data.yaml Controller ComputeHCI Compute
(undercloud) [stack@director ~]$ openstack flavor create --id auto --ram 4096 --disk 40 --vcpus 1 hci
(undercloud) [stack@director ~]$ openstack flavor set --property resources:VCPU=0 --property resources:MEMORY_MB=0 --property resources:DISK_GB=0 --property resources:CUSTOM_BAREMETAL=1 hci
(undercloud) [stack@director ~]$ openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="hci" hci
```

With that, we can proceed with the Introspection.

#### Introspection

The installation of the overcloud starts with registering the nodes for introspection.

_WARNING!_ The introspection of OpenStack Nodes includes a Cleanup phase.
During Cleanup any disks are wiped. While this makes sense for a dedicated
OpenStack node that is meant to join a cluster permanently, for the purpose of
our Beostack cluster where nodes may join temporarily and return to their
original role later on, this Cleanup may cause severe problems.

We intend to mitigate that challenge by cloning Flash Drives from existing
nodes without acutally going through a complete deployment. This step has not
been described yet and needs further investigation.


The Introspection statrs with importing a list of node descriptors like the following example:

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
     },
...
     {
      "pm_type": "fake_pxe",
      "mac": [
        "fc:aa:14:ff:a5:19"
      ],
      "name": "bx-hci1",
      "cpu": "4",
      "memory": "32768",
      "disk": "250",
      "arch": "x86_64",
      "capabilities": "node:hci-1,profile:hci,boot_option:local"
    },
...
    {
      "pm_type": "fake_pxe",
      "mac": [
        "74:d4:35:4e:39:98"
      ],
      "name": "bx-compute1",
      "cpu": "4",
      "memory": "16384",
      "disk": "250",
      "arch": "x86_64",
      "capabilities": "node:compute-1,profile:compute,boot_option:local"
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


#### Root Disk Assignment


In case the introspected nodes have more than one harddisk, we may want to make a clear assignment for the `root_drive` the Overcloud Installer stores the OS for the OpenStack node.
All required information about the the discovered hardware is stored in the Undercloud during introspection. We can query that information and assign the `root_drive` as appropriate

```
(undercloud) [stack@director ~]$ openstack baremetal node list
+--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
| UUID                                 | Name          | Instance UUID                        | Power State | Provisioning State | Maintenance |
+--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
| 6252cffd-eafb-4ec3-9473-1c9c7cf298fa | bx-controller | 0ee387e2-0c7c-4315-a757-11610052eb27 | power on    | deploying          | False       |
| 626b15cf-633f-4810-ab48-2f98d98afd4f | bx-compute1   | 1ee22a77-0377-49b4-9d21-d89a9333a0a1 | power on    | deploying          | False       |
| 5d667649-9c2b-4307-8fcf-7c695cf251c2 | bx-compute2   | 3f2970c9-3cd9-4702-ae0d-d00eac68c654 | power on    | deploying          | False       |
| 4fc5eb62-7022-460f-99f7-5214a4bebee9 | bx-compute3   | e54c2c9e-6447-442d-93ff-846405189f57 | power on    | deploying          | False       |
+--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
(undercloud) [stack@director ~]$ UUID=626b15cf-633f-4810-ab48-2f98d98afd4f
(undercloud) [stack@director ~]$ openstack baremetal introspection data save $UUID | jq ".inventory.disks"
[
  {
    "size": 250059350016,
    "serial": "S21PNSAG767030W",
    "wwn": "0x5002538da031d203",
    "rotational": false,
    "vendor": "ATA",
    "name": "/dev/sda",
    "wwn_vendor_extension": null,
    "hctl": "1:0:0:0",
    "wwn_with_extension": "0x5002538da031d203",
    "by_path": "/dev/disk/by-path/pci-0000:00:1f.2-ata-2.0",
    "model": "Samsung SSD 850"
  },
  {
    "size": 256641603584,
    "serial": "0330119070014981",
    "wwn": null,
    "rotational": true,
    "vendor": "Samsung",
    "name": "/dev/sdb",
    "wwn_vendor_extension": null,
    "hctl": "3:0:0:0",
    "wwn_with_extension": null,
    "by_path": "/dev/disk/by-path/fc---lun-0",
    "model": "Flash Drive FIT"
  }
]
(undercloud) [stack@director ~]$ openstack baremetal node set --property root_device='{"serial": "S21PNSAG767030W"}' $UUID
```

Installing the Overcloud Nodes on USB Flash Drives works just fine.

If available, an internal SSD may be used for the hyperconverged Ceph setup.



#### Network Setup

Probably the most challenging part of the OpenStack Overcloud deployment is the correct network configuation.
Regardless how few physical NICs we have, there is a lot of traffic and several different networks have to be prepared.

The following table gives a summary of the demo setup we use for this project.



network name | cidr            | VLAN | defroute      | DNS           | fixed IPs       | DHCP range    | Pool  | Extra    
-------------|-----------------|------|---------------|---------------|-----------------|---------------|-------|------
ctlplane     | 192.168.24.0/24 | 1   | 192.168.24.254 | 192.168.122.1 | local: 1 public: 2 admin: 3 fixed: 5 | instance: 10-34 inspect: 100-120 | 35-69 | EC2: 192.168.24.2
external     | 192.168.1.0/24  | 100 | 192.168.1.254  | 192.168.1.254 | 5               |               |       |
tenant       | 10.150.0.0/16   | 200 |                |               | 0.5             | 0.10-0.34     | 0.35-0.69 |
storage      | 172.16.1.0/24   | 201 |                |               | 5               | 10-34         |35-69 |
internal_api | 172.16.2.0/24   | 202 |                | | 5         | 10-34      | 35-69 |
storage_mgmt | 172.16.3.0/24   | 203 | | | 5         | 10-34      | 35-69 |
management   | 172.16.4.0/24   | 204 | | | 5         | 10-34      | 35-69 |



Some settings for the controlplane have already been declared in the undercloud.conf file. The other values are assigned in the [network-environment.yaml](/templates/network-environment.yaml) file. Like the table above, this file is fairly condensed and includes pretty much all required settings for our network environment.

The default node configuration uses abstract NIC assignemnts `nic1`, `nic2` which are mapped to the actual devices on the fly as they occur on the PCI bus. If this does not fit your needs, you may use the device names directly as shown in [controller.yaml](/templates/nic-configs/controller.yaml) and [compute.yaml](/templates/nic-configs/compute.yaml).


Scaling the Cluster
---------------------

The basic idea of the BeoStack Cluster is to integrate as much compute power into the cluster as possible.

However, the standard deployment workflow for OpenStack nodes is a) destructive and b) time consuming.

To allow hosts to join the cluster without replacing their current OS and
software, we use the USB Flash Drive as easy to add and replace storage. In
order to make the Cluster as flexible as possible, it would be nice if such USB
Flash Drives could just be moved around and plugged into arbitrary hosts as
they become available.

It appears, this is in fact the case.
While the original deployment cares about MAC address
for the boot device, the running Overcloud instance is pretty much independent of the
hardware and the details of the mainboard manufacturer.

In the Undercloud, the connection between the baremetal machine with its UUID and the Overcloud instance becomes invalid after moving the Flash Drive to another host.

To fix that you may undeploy and delete the original baremetal node in the Undercloud and then import a new record for the now migrated Flash host. This new baremetal node can then be adopted by the Undercloud. 

The image_source setting is required while the actual image is not used.

```
(undercloud) [stack@director ~]$ openstack baremetal node undeploy $UUID
(undercloud) [stack@director ~]$ openstack baremetal node delete $UUID
(undercloud) [stack@director ~]$ openstack overcloud node import ~/newhost.json
(undercloud) [stack@director ~]$ ironic node-update <NEWHOST> add instance_info/image_source="http://localhost:8088/overcloud-full.qcow2" instance_info/capabilities="{\"boot_option\": \"local\"}"
(undercloud) [stack@director ~]$ openstack baremetal node adopt <NEWUUID>
(undercloud) [stack@director ~]$ openstack baremetal node set --instance-uuid <OldInstanceUUID> <NEWUUID>
```

After undeploying the old node it may be reused to create another Flash Drive. 



Validation
---------------------

