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
