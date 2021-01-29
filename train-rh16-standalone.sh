#!/bin/bash

TEMPLATES_HOME=/usr/share/openstack-tripleo-heat-templates
CUSTOM_TEMPLATES=/home/stack/templates

if [ -f ./osjs.conf ]; then
	source ./osjs.conf
fi

if [ -z ${SUBMAN_USER} ]; then
	read -p "subscription-manager username: " SUBMAN_USER
fi

if [ -z ${SUBMAN_PASS} ]; then
	read -s -p "subscription-manager password: " SUBMAN_PASS
fi

if [ -z ${SUBMAN_POOL} ]; then
	read -p "subscription-manager pool: " SUBMAN_POOL
fi

if [ -z ${IP_ADDRESS} ]; then
	read -p "IP Address: " IP_ADDRESS
fi

if [ -z ${DNS_1} ]; then
	DNS_1=8.8.8.8
fi

if [ -z ${DNS_2} ]; then
	DNS_2=1.1.1.1
fi

function CONFIGURE_HOST {

subscription-manager register --username ${SUBMAN_USER} --password ${SUBMAN_PASS}
subscription-manager attach --pool=${SUBMAN_POOL}

dnf install -y dnf-utils

subscription-manager repos --disable=*
subscription-manager repos \
--enable=rhel-8-for-x86_64-baseos-rpms \
--enable=rhel-8-for-x86_64-appstream-rpms \
--enable=rhel-8-for-x86_64-highavailability-rpms \
--enable=ansible-2.9-for-rhel-8-x86_64-rpms \
--enable=openstack-16.1-for-rhel-8-x86_64-rpms \
--enable=fast-datapath-for-rhel-8-x86_64-rpms \
--enable=advanced-virt-for-rhel-8-x86_64-rpms

subscription-manager release --set=8.2

dnf module disable -y container-tools:rhel8
dnf module enable -y container-tools:2.0
dnf module disable -y virt:rhel
dnf module enable -y virt:8.2

dnf install -y python3-tripleoclient tmux git
dnf -y update
}


function PREINSTALL_CHECKLIST {
useradd stack
echo 'stack' | passwd --stdin stack
echo 'stack ALL=(root) NOPASSWD:ALL' | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack

mkdir ${CUSTOM_TEMPLATES}

cat <<EOF > /home/stack/templates/standalone.yaml
parameter_defaults:
  ContainerImagePrepare:
  - set:
      ceph_alertmanager_image: ose-prometheus-alertmanager
      ceph_alertmanager_namespace: registry.redhat.io/openshift4
      ceph_alertmanager_tag: 4.1
      ceph_grafana_image: rhceph-3-dashboard-rhel7
      ceph_grafana_namespace: registry.redhat.io/rhceph
      ceph_grafana_tag: 3
      ceph_image: rhceph-4-rhel8
      ceph_namespace: registry.redhat.io/rhceph
      ceph_node_exporter_image: ose-prometheus-node-exporter
      ceph_node_exporter_namespace: registry.redhat.io/openshift4
      ceph_node_exporter_tag: v4.1
      ceph_prometheus_image: ose-prometheus
      ceph_prometheus_namespace: registry.redhat.io/openshift4
      ceph_prometheus_tag: 4.1
      ceph_tag: latest
      name_prefix: openstack-
      name_suffix: ''
      namespace: registry.redhat.io/rhosp-rhel8
      neutron_driver: ovn
      rhel_containers: false
      tag: '16.1'
    tag_from_label: '{version}-{release}'
  ContainerImageRegistryCredentials:
    registry.redhat.io:
      ${SUBMAN_USER}: "${SUBMAN_PASS}"
  CloudName: ${IP_ADDRESS}
  ControlPlaneStaticRoutes: []
  Debug: true
  DeploymentUser: stack
  DnsServers:
    - ${DNS_1}
    - ${DNS_2}
  DockerInsecureRegistryAddress:
    - ${IP_ADDRESS}:8787
  NeutronPublicInterface: eth1
  NeutronBridgeMappings: datacentre:br-ctlplane
  NeutronPhysicalBridge: br-ctlplane
  StandaloneEnableRoutedNetworks: false
  StandaloneHomeDir: /home/stack
  StandaloneLocalMtu: 1500
  StandaloneExtraConfig:
    NovaComputeLibvirtType: qemu
  NtpServer: 0.pool.ntp.org
  # Domain
  NeutronDnsDomain: ootpa.local
  CloudDomain: ootpa.local
  CloudName: overcloud.ootpa.local
  CloudNameCtlPlane: overcloud.ctlplane.ootpa.local
  CloudNameInternal: overcloud.internalapi.ootpa.local
  CloudNameStorage: overcloud.storage.ootpa.local
  CloudNameStorageManagement: overcloud.storagemgmt.ootpa.local
EOF

cat <<EOF > /home/stack/deploy.sh
#!/bin/bash

sudo podman login registry.redhat.io --username ${SUBMAN_USER} --password ${SUBMAN_PASS}

sudo openstack tripleo deploy --templates \
--local-ip=${IP_ADDRESS}/24 \
-e ${TEMPLATES_HOME}/environments/standalone/standalone-tripleo.yaml \
-r ${TEMPLATES_HOME}/roles/Standalone.yaml \
-e ${CUSTOM_TEMPLATES}/standalone.yaml \
--output-dir /home/stack --standalone
EOF

chown -R stack:stack /home/stack
} 

function DEPLOY {
su --command 'tmux new-session -d -s "deploy" /home/stack/deploy.sh' stack
}

CONFIGURE_HOST
PREINSTALL_CHECKLIST
# DEPLOY
