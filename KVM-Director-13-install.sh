cat <<EOD >/root/ks.cfg
# Use CDROM installation media
install
cdrom
# Use text install
text
# Firewall configuration
firewall --enabled
# Keyboard layouts
keyboard --vckeymap=de --xlayouts='de'
# System language
# lang de_DE.UTF-8
lang us_US.UTF-8

firstboot --disable


# Network information
# br0		OpenStack Management	192.168.24.0/24
# enp0s20f0u3	Direkt Uplink		192.168.0.0/24
# enp0s20f0u4	OpenStack Tenant	192.168.1.0/24
# default	Libvirt Host		192.168.122.0/24
network --bootproto=static --device=eth0 --activate --ip=192.168.24.1 --netmask=255.255.255.0 --nodefroute --noipv6 --onboot=yes
network --bootproto=dhcp --device=eth1 --activate --onboot=yes --nodefroute --nodns
network --bootproto=static --device=eth2 --ip=192.168.1.30 --netmask=255.255.255.0 --activate --onboot=yes --nodefroute
network --bootproto=dhcp --device=eth3 --activate --onboot=yes
network  --hostname=director.bxlab.lunetix.org

# Root password
# python -c 'import crypt; print(crypt.crypt("My Password", "\$6\$_My_PieceOfGrain"))'
rootpw --iscrypted \$6\$oqLohaM3rcUJ\$HZtses1VFhkm7vdnzJwT6xdBS68fX9K4yLch6MIzu1k8RqRo4XZPeMMXKFOZDbW3BmSLvBOpUNL7ymUQWNSsI0
# SELinux configuration
selinux --enforcing
# System services
services --enabled="chronyd"
# Do not configure the X Window System
skipx
# System timezone
timezone Europe/Berlin --isUtc --ntpservers=0.rhel.pool.ntp.org,1.rhel.pool.ntp.org,2.rhel.pool.ntp.org

# Disk Partitioning
# Ignore all Disks except vda
ignoredisk --only-use=vda
# Partition clearing information
clearpart --none --initlabel
# Clear the Master Boot Record
zerombr
# System bootloader configuration
bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=vda
# Partition clearing information
clearpart --all --initlabel --drives=vda
# Partitioning
part /boot --fstype="xfs" --ondisk=vda --size=1024
part pv.01 --fstype="lvmpv" --ondisk=vda --size=61440
part pv.02 --fstype="lvmpv" --ondisk=vda --size=10240 --grow
volgroup vg_sys pv.01
volgroup vg_data pv.02
logvol /  --fstype="xfs" --percent=80 --name=root --vgname=vg_sys


# Preinstallation Scripts
%pre --logfile /root/ks-pre.log
%end

# Postinstallation Scripts
%post --logfile /root/ks-post.log

subscription-manager register --org=1234567 --activationkey=rhel-f4b48b02-534a-4fec-a456-d82a37cb5042
subscription-manager repos --disable="*"
subscription-manager repos \\
    --enable=rhel-7-server-rpms \\
    --enable=rhel-7-server-extras-rpms \\
    --enable=rhel-7-server-rh-common-rpms \\
    --enable=rhel-ha-for-rhel-7-server-rpms \\
    --enable=rhel-7-server-openstack-13-rpms \\
    --enable=rhel-7-server-rhceph-3-tools-rpms

subscription-manager release --unset

yum -y update
mkdir -m0700 /root/.ssh/
cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDaAPSlXxIZqmYTESbtDBo3MfcFwcsEruy9rhUe6+1nAv65oKaugdD7Vqk5dOY57tYmYoXsf+YSsxwDdnNUCFM5me8bWbtFaIMdrjYh2MN6YJx0//Sm6b7m65oVF+FPb2PjmfJJm3byDePuUkUXKj58alNz4FpXJChfzEmJAlmBKexunasyX1vInFF+5LWftcSa5LSPXKLSIF/Oq/bkf8FxubM55JA/xZujyLUJaVC3pN2ixZzVvmM0lqzYOY2SEqNCESB+4q6pNLF/wXPyI+rbJX+brLih1MP3nAofYk64zWmr8yOt6Dp3QH9rzIRY1QLf8lZPRNJo9zYG8KeP4Inz shetze@shetze.remote.csb
EOF
chmod 0600 /root/.ssh/authorized_keys
restorecon -R /root/.ssh/

yum -y install rng-tools
systemctl enable --now rngd

useradd stack
echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack
sudo -i -u stack mkdir /home/stack/images
sudo -i -u stack mkdir /home/stack/templates

cat <<EOF >>/etc/hosts
192.168.24.1 \$(hostname) director
EOF

yum install -y python-tripleoclient
yum install -y ceph-ansible

USERID='1234567|-director.bxlab'
SECRET=''

# sudo -i -u stack openstack undercloud install


%end

# Packages
%packages
@^Minimal Install
vim-enhanced
wget
git
net-tools
bind-utils
bash-completion
kexec-tools
sos
psacct
ipa-client

#@^Server
#@^Server with GUI
#@^Workstation
#@^Virtualization Host
#@^Custom Operating System

#@RPM Development Tools
#@Container Management
#@Smart Card Support
#@.NET Core Development
#@Network Servers
#@Development Tools
#@Headless Management
#@System Tools
#@Graphical Administration Tools
#@Scientific Support
#@Security Tools
#@Legacy UNIX Compatibility
%end
EOD

virt-install \
--name director13.bxlab.lunetix.org \
--description "OSCP Director 13" \
--os-type=Linux \
--os-variant=rhel7.6 \
--ram=24576 \
--vcpus=4 \
--disk path=/var/lib/libvirt/images/RHOS-D13.qcow2,bus=virtio,size=100 \
--network bridge=br0,model=virtio \
--network type=direct,source=enp0s20f0u3,source_mode=bridge,model=virtio \
--network type=direct,source=enp0s20f0u4,source_mode=bridge,model=virtio \
--network default \
--initrd-inject /root/ks.cfg \
--location /srv/Images/ISO/rhel-server-7.7-x86_64-dvd.iso \
--extra-args="ks=file:/ks.cfg"

# br0		OpenStack Management	192.168.24.0/24
# enp0s20f0u3	Direkt Uplink		192.168.0.0/24
# enp0s20f0u4	OpenStack Tenant	192.168.1.0/24
# default	Libvirt Host		192.168.122.0/24
