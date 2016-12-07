#!/usr/bin/env bash

set -e

: ${STEMCELL_NAME:?}
: ${BAT_VCAP_PASSWORD:?}
: ${BOSH_USER:?}
: ${BOSH_PASSWORD:?}

source pipelines/shared/utils.sh
source /etc/profile.d/chruby.sh
chruby 2.1.7

# outputs
output_dir=$(realpath bats-config)
bats_spec="${output_dir}/bats-config.yml"
bats_env="${output_dir}/bats.env"

# inputs
bats_dir=$(realpath bats)
director_state_dir=$(realpath director-state)
director_ip=`cat "${director_state_dir}/director-info"`

# env file generation
cat > "${bats_env}" <<EOF
#!/usr/bin/env bash
export BAT_DIRECTOR=${director_ip}
export BAT_DNS_HOST=${director_ip}
export BAT_INFRASTRUCTURE=softlayer
export BAT_NETWORKING=dynamic
export BAT_DEBUG_MODE=true
export BAT_VCAP_PASSWORD=${BAT_VCAP_PASSWORD}
export BAT_RSPEC_FLAGS="--tag ~vip_networking --tag ~manual_networking --tag ~root_partition --tag ~raw_ephemeral_storage"
export BAT_DIRECTOR_USER="${BOSH_USER}"
export BAT_DIRECTOR_PASSWORD="${BOSH_PASSWORD}"
EOF

pushd "${bats_dir}" > /dev/null
  ./write_gemfile
  bundle install
  bundle exec bosh -n target "${director_ip}"
  BOSH_UUID="$(bundle exec bosh status --uuid)"
popd > /dev/null

cat > "${bats_spec}" <<EOF
---
cpi: softlayer
properties:
  uuid: ${BOSH_UUID}
  pool_size: 1
  instances: 1
  second_static_ip: ${BAT_SECOND_STATIC_IP}
  stemcell:
    name: ${STEMCELL_NAME}
    version: latest
  cloud_properties:
    bosh_ip: ${director_ip}
    public_vlan_id: ${SL_VLAN_PUBLIC}
    private_vlan_id: ${SL_VLAN_PRIVATE}
    vm_name_prefix: ${SL_VM_NAME_PREFIX}
    data_center: ${SL_DATACENTER}
    domain: ${SL_VM_DOMAIN}
  networks:
  - name: default
    type: dynamic
    dns:
    - ${director_ip}
  password: "\$6\$3n/Y5RP0\$Jr1nLxatojY9Wlqduzwh66w8KmYxjoj9vzI62n3Mmstd5mNVnm0SS1N0YizKOTlJCY5R/DFmeWgbkrqHIMGd51"
EOF