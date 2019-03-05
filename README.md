How To deploy a RHEL instance with full disk encryption into the Azure Cloud
============================================================================

Use Case: Fully Encrypted Disks for RHEL Cloud Instances
--------------------------------------------------------

#### Primary Actor
Ops Admin
#### Goal in Context
Have functional, fully encrypted, cost efficient, flexible and reliable RHEL instance deployed into the Cloud for legacy database application purposes.
#### Scope
System
#### Level
Summary
#### Stakeholders and Interests
* Business: use cheap storage backend
* Security: data integrity, confidentiality and availability need to be maintained
* Operations:
  * deployment needs to be fully automated
  * no manual intervention on boot time
  * key renewal must be automated
* Application Owner: DB performance equal to on premise
#### Precondition
* Existing account in cloud
* two or more RHEL subscriptions
#### Minimal Guarantees
OS and data disk encryption
#### Success Guarantees
#### Trigger
Security Compliance Rules
#### Main Success Scenario
#### Extensions
* RAID0 or LVM Striping may be used to improve performance
* partitions may grow if required
#### Technology & Data Variations List
* LUKS disk encryption
* NBDE key management
* virt-manager image/instance creation
* Anaconda kickstart




Preparation: Tang Server
------------------------

For the encryption key management, a Tang server needs to be available in your network.

```bash
TANG_PORT=8089
yum install -y tang
sed -i "s/ListenStream=.*/ListenStream=$TANG_PORT/g" /usr/lib/systemd/system/tangd.socket
firewall-cmd --add-port=$TANG_PORT/tcp
firewall-cmd --add-port=$TANG_PORT/tcp --permanent
yum install -y policycoreutils-python
semanage port -a -t http_port_t -p tcp $TANG_PORT
systemctl enable tangd.socket --now
curl http://localhost:$TANG_PORT
SIG_JWK=$(grep -l ES512 /var/db/tang/*)
SIG_THP=$(jose jwk thp -i $SIG_JWK)
echo TANG_BINDING="{\"url\":\"http://\$TANG_SERVER:$TANG_PORT\",\"thp\":\"$SIG_THP\"}"
```

The default port for Tang is 80. The example above shows how to move Tang to another port.

You may want to write down and keep the TANG_BINDING for further use with the NBDE clients.


Deployment Encrypted OS Disk
----------------------------


In order to deploy a fully encrypted disk, you need to kickstart the
installation from scratch and then move the encrypted image into the cloud.
For Azure the process is described in [1]

As shortcut we use the following Kickstart file:

```bash
lang en_US
keyboard us
timezone America/New_York --isUtc
text
skipx
# reboot

auth --passalgo=sha512 --useshadow
rootpw redhat --plaintext

cdrom

bootloader --location=mbr --append="earlyprintk=ttys0 console=ttys0 rootdelay=300"
zerombr
clearpart --all --initlabel
part /boot --fstype="xfs" --ondisk=vda --size=256
part pv.tang --fstype="lvmpv" --ondisk=vda --grow --encrypted --passphrase='ALYhABIDyJuRDAjew2Utub@jONti'
volgroup rhel --pesize=4096 pv.tang
logvol / --fstype="xfs" --size=5120 --name=root --vgname=rhel
logvol swap --fstype="swap" --size=2048 --name=swap --vgname=rhel

selinux --enforcing
firewall --enabled --ssh
firstboot --disable

%packages --excludedocs
@core
clevis-dracut
%end

%post
TANG_SERVER=85.25.159.110:8089
SIG_THP=ac_uUhM5qY6mv-6jiv-ORFw-OtI
ORG_ID=6502464
ACTIVATION_KEY=rhel-d0735c7e-70a9-42b6-ac5d-b2d9ee65ccee

# bind LUKS disk encryption to Tang server
TANG_BINDING="{\"url\":\"http://$TANG_SERVER\",\"thp\":\"$SIG_THP\"}"
LUKS_PW='ALYhABIDyJuRDAjew2Utub@jONti'

clevis luks bind -f -k- -d /dev/vda2 tang $TANG_BINDING <<< $LUKS_PW
cryptsetup luksRemoveKey /dev/vda2 <<< $LUKS_PW


# generic post installation as described in https://access.redhat.com/articles/2728301

# Add the Hyper-V drivers
echo "add_drivers+=\" hv_vmbus \" " >> /etc/dracut.conf
echo "add_drivers+=\" hv_netvsc \" " >> /etc/dracut.conf
echo "add_drivers+=\" hv_storvsc \" " >> /etc/dracut.conf
dracut -f -v

# Stop and remove cloud-init
systemctl stop cloud-init
yum remove -y cloud-init

# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
USERCTL="no"
PEERDNS="yes"
IPV6INIT="no"
EOF

# Remove any persistent network device rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/75-persistent-net-generator.rules

# Set the network service to start automatically
chkconfig network on

# Configure sshd
systemctl enable sshd

# Enable ssh keepalive
sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

# Remove GRUB parameters: crashkernel=auto, rhgb, quiet
export grub_cmdline=`grep -n 'GRUB_CMDLINE_LINUX' /etc/default/grub | awk -F ':' '{print $1}'`
sed -i -e "${grub_cmdline}s:\(crashkernel=auto\|rhgb\|quiet\)::g" -e "${grub_cmdline}s:\" :\":" -e "${grub_cmdline}s: \":\":" -e "${grub_cmdline}s:\s\s\+: :g" /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# Register with the Red Hat Subscription Manager
subscription-manager register --org=$ORG_ID --activationkey=$ACTIVATION_KEY

# Enable the RHEL 7.x extras repo
subscription-manager repos --enable=rhel-7-server-extras-rpms

# Install the latest software update
yum update -y

# Install the Microsoft Azure Linux Agent
yum install -y WALinuxAgent

# Enable the Azure agent at boot-up
systemctl enable waagent.service

# Configure swap in WALinuxAgent
sed -i 's/^\(ResourceDisk\.EnableSwap\)=[Nn]$/\1=y/g' /etc/waagent.conf
sed -i 's/^\(ResourceDisk\.SwapSizeMB\)=[0-9]*$/\1=2048/g' /etc/waagent.conf
sed -i 's/^\(Provisioning\.DeleteRootPassword\)=[Yy]$/\1=n/g' /etc/waagent.conf
sed -i 's/^\(ResourceDisk\.Filesystem\)=.*$/\1=xfs/g' /etc/waagent.conf

# Unregister with the Red Hat subscription manager
subscription-manager unregister

# Disable the root account
usermod root -p '!!'

# Deprovision and prepare for Azure
waagent -force -deprovision
%end
```


The following script requires virt-manager to be installed on a system prepared as a Azure Administration Server as described in [1].

A new VM image is created using the kickstart file above (provided from the local directory via http by a SimpleHTTPServer).
That image is then aligned and converted into the Azure vhd image which is finally uploaded into the existing storage container.
The "az vm create" generates the SSH keys on the fly in the ~/.ssh directory.


```bash
INSTANCE_NAME=NBDE-Client
INSTANCE_NUMBER=01
python -m SimpleHTTPServer 80 &
virt-install -n  $INSTANCE_NAME-$INSTANCE_NUMBER --memory 4096 --vcpus 4 --os-variant rhel7.4 --accelerate --network network=default --disk size=10 \
--location /srv/Images/ISO/rhel-server-7.5-x86_64-dvd.iso \
--graphics none \
--extra-args "ks=http://localhost/kickstart/NBDE-Client.ks console=ttyS0 ip=dhcp inst.sshd"

qemu-img convert -f qcow2 -O raw /var/lib/libvirt/images/$INSTANCE_NAME-$INSTANCE_NUMBER.qcow2 /var/lib/libvirt/images/$INSTANCE_NAME-$INSTANCE_NUMBER.raw
MB=$((1024 * 1024))
size=$(qemu-img info -f raw --output json /var/lib/libvirt/images/$INSTANCE_NAME-$INSTANCE_NUMBER.raw | gawk 'match($0, /"virtual-size": ([0-9]+),/, val) {print val[1]}')
rounded_size=$((($size/$MB + 1) * $MB))
if [ $(($size % $MB)) -eq  0 ]
then
 echo "Your image is already aligned. You do not need to resize."
else
 echo "The image is not aligned, resizing to $rounded_size."
 qemu-img resize -f raw /var/lib/libvirt/images/$INSTANCE_NAME-$INSTANCE_NUMBER.raw $rounded_size
fi
qemu-img convert -f raw -o subformat=fixed -O vpc /var/lib/libvirt/images/$INSTANCE_NAME-$INSTANCE_NUMBER.raw /var/lib/libvirt/images/$INSTANCE_NAME-$INSTANCE_NUMBER.vhd
az storage blob upload --account-name osdiskaccount --container-name osdiskcontainer --type page --file /var/lib/libvirt/images/$INSTANCE_NAME-$INSTANCE_NUMBER.vhd --name $INSTANCE_NAME-$INSTANCE_NUMBER.vhd
IMAGE_URL=$(az storage blob url -c osdiskcontainer -n $INSTANCE_NAME-$INSTANCE_NUMBER.vhd)
az image create -n $INSTANCE_NAME-$INSTANCE_NUMBER -g Disk-Encryption -l westeurope --source $IMAGE_URL --os-type linux
az vm create -g Disk-Encryption -l westeurope -n $INSTANCE_NAME-$INSTANCE_NUMBER --vnet-name Disk-Encryption-vnet --subnet default --size Standard_A2 --os-disk-name $INSTANCE_NAME-$INSTANCE_NUMBER-osdisk --admin-username superuser --generate-ssh-keys --image $IMAGE_URL
```


The critical detail with this installation is the network connection to the
Tang server.  We need to make sure the same Tang server (IP address, key DB) is
accessible both from the libvirt/KVM site where the kickstart installation is
performed and from the cloud account where the final instance will run.  For
that purpose it is perfectly feasible to use a public availabe Tang server
during the installation, like the one exposed in the example above. The very
nature of the Clevis/Tang protocol makes sure the Tang server does never store
or even see the actual encryption key [2]. It is sufficient and possible to add
a second Tang server after the instance has reached its final destination.
However, for the first boot in that environment the first public Tang server still
needs to be available in order to decrypt the root disk.

It is also worth noting that all instances derived from the same encrypted base
image share one LUKS master key. If this is not acceptable, every instance
needs to be kickstarted seperately.

Encryption of Data Disk
-----------------------

Independent of the OS disk encryption demonstrated above, additional data disks will be encrypted.

The following script depends on two additional disk ressources attached to the VM instance, /dev/sdc and /dev/sdd

Both disks will be encrypted and combined into one VG. For demonstration a LV
is created using 2 stripes to distribute the data between the two disks.



```bash
yum -y install clevis-systemd luksmeta
#
TEMP_PW=$(pwmake 128)
TANG_SERVER=85.25.159.110:8089
SIG_THP=ac_uUhM5qY6mv-6jiv-ORFw-OtI
TANG_BINDING="{\"url\":\"http://$TANG_SERVER\",\"thp\":\"$SIG_THP\"}"
#
cryptsetup luksFormat /dev/sdc - <<<$TEMP_PW
clevis luks bind -f -k- -d /dev/sdc tang $TANG_BINDING <<< $TEMP_PW
cryptsetup luksRemoveKey /dev/sdc <<< $TEMP_PW
#
cryptsetup luksFormat /dev/sdd - <<<$TEMP_PW
clevis luks bind -f -k- -d /dev/sdd tang $TANG_BINDING <<< $TEMP_PW
cryptsetup luksRemoveKey /dev/sdd <<< $TEMP_PW
#
systemctl enable clevis-luks-askpass.path
systemctl start clevis-luks-askpass.path
echo "sdc_crypt /dev/sdc none _netdev" >>/etc/crypttab
echo "sdd_crypt /dev/sdd none _netdev" >>/etc/crypttab
systemctl restart cryptsetup.target
#
pvcreate /dev/mapper/sdc_crypt
pvcreate /dev/mapper/sdd_crypt
vgcreate data /dev/mapper/sdc_crypt /dev/mapper/sdd_crypt
lvcreate -i2 -L10G -n data01 data
mkfs.xfs /dev/mapper/data-data01
mkdir /srv/data01
echo "/dev/mapper/data-data01 /srv/data01 xfs _netdev 0 0" >>/etc/fstab
mount -a
```

High Availability
-----------------

The recommended setup to achieve HA for NBDE is to bind a client to multiple Tang servers.

After throwing away the temporary LUKS key during the kickstart installation
above, it is not really obvious how to add additional Tang servers later on.
The same problem arises if you want to rotate Tang keys as recommended in the
documentation.

The following script shows how to do the trick: use the existing Tang server to
manually decrypt the key stored in the LUKS metadata.

```bash
luksmeta show -d /dev/sda2
luksmeta load -d /dev/sda2 -s 1  > meta-slot1.enc
clevis decrypt tang < meta-slot1.enc > meta-slot1.dec
SECOND_TANG_SERVER=10.0.0.4:8089
SIG_THP=oEoQ2zYdy4M6r0lpS5QubQNIH_c
TANG_BINDING="{\"url\":\"http://$SECOND_TANG_SERVER\",\"thp\":\"$SIG_THP\"}"
clevis luks bind -f -k meta-slot1.dec -d /dev/sda2 tang $TANG_BINDING
rm -f meta-slot1.enc meta-slot1.dec
luksmeta show -d /dev/sda2
```


Verification
------------

The VM instance created above is starting up and you can log in using SSH and the public IP address provided by Azure
```bash
ssh -i ~/.ssh/id_rsa superuser@$publicIpAddress
```

The root partition is in LVM and the PV is encrypted with LUKS
```bash
sudo lvdisplay | grep 'LV Path'
sudo pvdisplay | grep 'PV Name' | grep luks
sudo luksmeta show -d /dev/sda2
```



[1] https://access.redhat.com/articles/uploading-rhel-image-to-azure

[2] https://github.com/latchset/tang

[3] https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Security_Guide/sec-Using_Network-Bound_Disk_Encryption.html

[4] http://www.admin-magazine.com/Archive/2018/43/Automatic-data-encryption-and-decryption-with-Clevis-and-Tang

