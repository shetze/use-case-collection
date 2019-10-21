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
# enp0s20f0u4	OpenStack External	192.168.1.0/24
# default	Libvirt Host		192.168.122.0/24
network --bootproto=static --device=enp1s0 --ip=192.168.24.1 --netmask=255.255.255.0 --activate --nodefroute --noipv6 --onboot=yes
network --bootproto=dhcp --device=ens2s0 --activate --onboot=yes --nodefroute --nodns
network --bootproto=static --device=enp3s0 --ip=192.168.1.30 --netmask=255.255.255.0 --vlanid=100 --activate --onboot=yes --nodefroute
network --bootproto=dhcp --device=enp4s0 --activate --onboot=yes
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


syspurpose --role="Red Hat Enterprise Linux Server" --sla="Self-Support" --usage="Development/Test"


# Preinstallation Scripts
%pre --logfile /root/ks-pre.log
%end

# Postinstallation Scripts
%post --logfile /root/ks-post.log

subscription-manager register --org=1234567 --activationkey=rhel-f4b48b02-534a-4fec-a456-d82a37cb5042
subscription-manager repos --disable="*"
subscription-manager repos \\
    --enable=rhel-8-for-x86_64-baseos-rpms \\
    --enable=rhel-8-for-x86_64-supplementary-rpms \\
    --enable=rhel-8-for-x86_64-appstream-rpms \\
    --enable=rhel-8-for-x86_64-highavailability-rpms \\
    --enable=ansible-2.8-for-rhel-8-x86_64-rpms  \\
    --enable=advanced-virt-for-rhel-8-x86_64-rpms  \\
    --enable=satellite-tools-6.5-for-rhel-8-x86_64-rpms  \\
    --enable=fast-datapath-for-rhel-8-x86_64-rpms \\
    --enable=openstack-15-for-rhel-8-x86_64-rpms

#    --enable=rhel-8-for-x86_64-sap-solutions-rpms \\
#    --enable=rhel-8-for-x86_64-sap-netweaver-rpms \\
#    --enable=ansible-2-for-rhel-8-x86_64-rpms \\
#    --enable=rh-sso-7.3-for-rhel-8-x86_64-rpms \\
#    --enable=jb-coreservices-1-for-rhel-8-x86_64-rpms \\
#    --enable=jb-eap-7.2-for-rhel-8-x86_64-rpms \\
#    --enable=rhv-4-mgmt-agent-for-rhel-8-x86_64-rpms \\
#    --enable=cert-1-for-rhel-8-x86_64-rpms \\


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
192.168.1.30 \$(hostname) director
EOF

yum install -y python3-tripleoclient
# yum install -y ceph-ansible

sudo -i -u stack openstack tripleo container image prepare default \\
  --local-push-destination \\
  --output-env-file containers-prepare-parameter.yaml

USERID='1234567|director.bxlab'
SECRET=''

cat <<EOF >>/home/stack/containers-prepare-parameter.yaml
  ContainerImageRegistryCredentials:
    registry.redhat.io:
      '\${USERID}': '\${SECRET}'

EOF

sudo -i -u stack cp /usr/share/python-tripleoclient/undercloud.conf.sample /home/stack/undercloud.conf

sudo -i -u stack mkdir /home/stack/.docker

sudo -i -u stack podman login -u "\$USERID" -p "\$SECRET" --authfile=/home/stack/.docker/config.json https://registry.redhat.io

REGISTRY_AUTH_FILE=/home/stack/.docker/config.json

sudo -i -u stack skopeo inspect --authfile=\$REGISTRY_AUTH_FILE docker://registry.redhat.io/rhosp15-rhel8/openstack-cron

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
--name director.bxlab.lunetix.org \
--description "OSCP Director" \
--os-type=Linux \
--os-variant=rhel8.0 \
--ram=24576 \
--vcpus=4 \
--disk path=/dev/sda1,bus=virtio \
--network bridge=br0,model=virtio \
--network type=direct,source=enp0s20f0u3,source_mode=bridge,model=virtio \
--network type=direct,source=enp0s20f0u4,source_mode=bridge,model=virtio \
--network default \
--initrd-inject /root/ks.cfg \
--location /srv/Images/ISO/rhel-8.0-x86_64-dvd.iso \
--extra-args="ks=file:/ks.cfg"
