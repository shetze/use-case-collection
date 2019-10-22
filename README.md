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


Preparation1: IPA and Satellite
-------------------------------
As basic network infrastructure components, RHEL IPA and Red Hat Satellite come in handy.
In case these services do not exist yet, the provided Kickstart examples [Kickstart/ipa-ks.cfg] and [Kickstart/sat65-ks.cfg] help to set up these services from scratch.
You will exchange the authorization credentials and the Activation Key with your own, and you probably need to adjust the network settings to fit your environment.

The IPA server can be used as CA to sign external SSL certifiates for the OpenStack cloud.


Implementation Part 1: Undercloud Deployment
--------------------------------------------

The Director instance may be running as a virtual machine somewhere. In fact, it is quite useful to do so, because such an VM can be snapshotted and easily recovered in case something breaks.

To deploy the Director as a simple KVM instance, the provided [KVM-Director-13-install.sh]
You will exchange the authorization credentials and the Activation Key with your own, and you probably need to adjust the network settings to fit your environment.
scripts encapsulate the virt-install together with the appropriate Kickstart file for the libvirt deployment.

After the Kickstart installation has finished, 




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





Implementation Part 2: Overcloud Deployment
-------------------------------------------





Validation
---------------------

