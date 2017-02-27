#!/usr/bin/env bash

set -e

: ${BOSH_CLIENT:?}
: ${BOSH_CLIENT_SECRET:?}
: ${SL_VM_NAME_PREFIX:?}
: ${SL_VM_DOMAIN:?}
: ${SL_DATACENTER:?}
: ${SL_VLAN_PUBLIC:?}
: ${SL_VLAN_PRIVATE:?}
: ${RELEASE_NAME:?}
: ${STEMCELL_NAME:?}
: ${DEPLOYMENT_NAME:?}

source pipelines/shared/utils.sh

# inputs
bosh_cli=$(realpath bosh-cli/bosh-cli-*)
chmod +x $bosh_cli

# outputs
manifest_dir="$(realpath deployment-manifest)"

DIRECTOR_IP = ""

export BOSH_ENVIRONMENT="${DIRECTOR_IP//./-}.sslip.io"

cat > "${manifest_dir}/deployment.yml" <<EOF
---
name: ${DEPLOYMENT_NAME}

releases:
  - name: ${RELEASE_NAME}
    version: latest

compilation:
  reuse_compilation_vms: true
  workers: 1
  network: private
  cloud_properties:
    cpu: 2
    ram: 1024
    disk: 10240

update:
  canaries: 1
  canary_watch_time: 30000-240000
  update_watch_time: 30000-600000
  max_in_flight: 3

resource_pools:
  - name: default
    stemcell:
      name: ${STEMCELL_NAME}
      version: latest
    network: private
    cloud_properties:
      vmNamePrefix: $SL_VM_NAME_PREFIX
      domain: $SL_VM_DOMAIN
      startCpus: 4
      maxMemory: 8192
      ephemeralDiskSize: 100
      datacenter:
        name: $SL_DATACENTER
      hourlyBillingFlag: true
      localDiskFlag: false
      primaryNetworkComponent:
        networkVlan:
          id: $SL_VLAN_PUBLIC
      primaryBackendNetworkComponent:
        networkVlan:
          id: $SL_VLAN_PRIVATE
    env:
      bosh:
        # c1oudc0w is a default password for vcap user
        password: "$6$4gDD3aV0rdqlrKC$2axHCxGKIObs6tAmMTqYCspcdvQXh3JJcvWOY2WGb4SrdXtnCyNaWlrf3WEqvYR2MYizEGp3kMmbpwBC6jsHt0"
        keep_root_password: true

networks:
  - name: default
    type: dynamic
    dns:
    - ${DIRECTOR_IP}
    - 10.0.80.11
    - 10.0.80.12

jobs:
  - name: simple
    template: simple
    instances: 1
    resource_pool: default
    networks:
      - name: default
        default: [dns, gateway]
EOF
