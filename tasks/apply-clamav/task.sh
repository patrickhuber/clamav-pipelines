#!/bin/bash
set -eu

export BOSH_ENVIRONMENT=https://$(cat pcf-bosh-creds/director_ip):25555
export BOSH_CLIENT=$(cat pcf-bosh-creds/bosh-username)
export BOSH_CLIENT_SECRET=$(cat pcf-bosh-creds/bosh-pass)
export BOSH_CA_CERT=pcf-bosh-creds/bosh-ca.pem

# export the runtime config
mkdir -p bosh_info
bosh runtime-config > bosh_info/runtime-config

# if the clamav addon exists in the runtime config
bosh int bosh_info/runtime-config --path /addons/name=clamav 2> /dev/null
exists_in_runtime_config=$?

if [ "$exists_in_runtime_config" -eq 0]; then

    # remove it from the runtime config
    bosh int bosh_info/runtime-config -op clamav-pipelines/ops/remove-clamav-addon.yml > bosh_info/runtime-config

    # update bosh
    bosh update-config bosh_info/runtime-config
fi

# get the pivnet resource version of clamav    
target_clamav_version = $(bosh int clamav-addon/metadata.yml --path /release/version)

# export the named runtime config
bosh runtime-config -name=clamav > bosh_info/clamav-runtime-config 2> /dev/null

# if the named runtime exists
if ["$?" -eq 0]; then    

    # and get the installed version of clamav
    installed_clamav_version = $(bosh int bosh_info/runtime-config --path /releases/name=clamav/version)

    # if versions match, exit
    if ["$installed_clamav_version" -eq "$target_clamav_version"]; then
        exit 0
    fi
fi

# upload the new version of clamav
bosh upload-release clamav-addon/clamav-$target_clamav_version.tgz

# create the interpolated named runtime config 
# overwrite it if it exists because we don't care what version is installed
bosh int clamav-pipelines/runtime.yml \
    -v database_mirror_ip=$DATABASE_MIRROR_IP \
    -v clamav_version=$target_clamav_version \
    > bosh_info/clamav-runtime-config

# update the clamav runtime config
bosh update-config \
  --type=runtime \
  --name=clamav \
  bosh_info/clamav-runtime-config

# should we cleanup the old release version? this would be the time
# bosh delete-release clamav/$installed_clamav_version