#!/usr/bin/env bash

set -e

source pipelines/shared/utils.sh

: ${SL_VM_NAME_PREFIX:?}
: ${SL_VM_DOMAIN:?}
: ${SL_DATACENTER:?}
: ${SL_VLAN_PUBLIC:?}
: ${SL_VLAN_PRIVATE:?}
: ${SL_USERNAME:?}
: ${SL_API_KEY:?}
: ${BOSH_CLIENT:?}
: ${BOSH_CLIENT_SECRET:?}
: ${USE_REDIS:=false}

# inputs
# paths will be resolved in a separate task so use relative paths
BOSH_RELEASE_URI="file://$(echo bosh-release/*.tgz)"
CPI_RELEASE_URI="file://$(echo cpi-release/*.tgz)"
STEMCELL_URI="file://$(echo stemcell/*.tgz)"

# outputs
output_dir="$(realpath director-config)"

redis_job=""
if [ "${USE_REDIS}" == true ]; then
  redis_job="- {name: redis, release: bosh}"
fi

# env file generation
cat > "${output_dir}/director.env" <<EOF
#!/usr/bin/env bash

export BOSH_ENVIRONMENT="${DIRECTOR_IP//./-}.sslip.io"
export BOSH_CLIENT=${BOSH_CLIENT}
export BOSH_CLIENT_SECRET=${BOSH_CLIENT_SECRET}
EOF

cat > "${output_dir}/director.yml" <<EOF
---
name: certification-director

releases:
  - name: bosh
    url: ${BOSH_RELEASE_URI}
  - name: bosh-softlayer-legacy-cpi
    url: ${CPI_RELEASE_URI}

resource_pools:
  - name: vms
    network: default
    stemcell:
      url: ${STEMCELL_URI}
    cloud_properties:
      deployedByBoshcli: true
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
        password: "$6$4gDD3aV0rdqlrKC$2axHCxGKIObs6tAmMTqYCspcdvQXh3JJcvWOY2WGb4SrdXtnCyNaWlrf3WEqvYR2MYizEGp3kMmbpwBC6jsHt0"
        keep_root_password: true

disk_pools:
  - name: disks
    disk_size: 20_000

networks:
  - name: default
    type: dynamic
    dns:
    - 8.8.8.8
    - 10.0.80.11
    - 10.0.80.12

jobs:
  - name: bosh
    instances: 1

    templates:
      - {name: nats, release: bosh}
      - {name: postgres-9.4, release: bosh}
      - {name: blobstore, release: bosh}
      - {name: director, release: bosh}
      - {name: health_monitor, release: bosh}
      - {name: powerdns, release: bosh}
      - {name: softlayer_legacy_cpi, release: bosh-softlayer-legacy-cpi}
      ${redis_job}

    resource_pool: vms
    persistent_disk_pool: disks

    networks:
      - name: default

    properties:
      nats:
        address: 127.0.0.1
        user: nats
        password: nats-password

      postgres: &db
        host: 127.0.0.1
        user: postgres
        password: postgres-password
        database: bosh
        adapter: postgres

      # required for some upgrade paths
      redis:
        listen_addresss: 127.0.0.1
        address: 127.0.0.1
        password: redis-password

      blobstore:
        address: 127.0.0.1
        port: 25250
        provider: dav
        director: {user: director, password: director-password}
        agent: {user: agent, password: agent-password}

      director:
        address: 127.0.0.1
        name: certification-director
        db: *db
        cpi_job: softlayer_legacy_cpi
        user_management:
          provider: local
          local:
            users:
              - {name: ${BOSH_CLIENT}, password: ${BOSH_CLIENT_SECRET}}
        enable_virtual_delete_vms: true

      hm:
        http: {user: hm, password: hm-password}
        director_account: {user: ${BOSH_DIRECTOR_USERNAME}, password: ${BOSH_DIRECTOR_PASSWORD}}
        resurrector_enabled: true

      agent: {mbus: "nats://nats:nats-password@127.0.0.1:4222"}

      dns:
        address: 127.0.0.1
        db: *db

      softlayer_legacy: &softlayer
        username: $SL_USERNAME
        apiKey: $SL_API_KEY

cloud_provider:
  template: {name: softlayer_legacy_cpi, release: bosh-softlayer-legacy-cpi}

  mbus: "https://mbus:mbus-password@$SL_VM_NAME_PREFIX.$SL_VM_DOMAIN:6868"

  properties:
    softlayer_legacy: *softlayer
    agent: {mbus: "https://mbus:mbus-password@0.0.0.0:6868"}
    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}
    ntp: [0.pool.ntp.org, 1.pool.ntp.org]
EOF
