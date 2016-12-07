#!/usr/bin/env bash

set -e

: ${BOSH_PASSWORD:?}
: ${BOSH_USER:?}
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
      VmNamePrefix: $SL_VM_NAME_PREFIX
      Domain: $SL_VM_DOMAIN
      StartCpus: 4
      MaxMemory: 8192
      EphemeralDiskSize: 100
      Datacenter:
        Name: $SL_DATACENTER
      HourlyBillingFlag: true
      LocalDiskFlag: false
      PrimaryNetworkComponent:
        NetworkVlan:
          Id: $SL_VLAN_PUBLIC
      PrimaryBackendNetworkComponent:
        NetworkVlan:
          Id: $SL_VLAN_PRIVATE

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
