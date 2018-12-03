#!/bin/bash
set -eu

source pcf-bosh-creds/bosh2_commandline_credentials
export BOSH_CLIENT
export BOSH_CLIENT_SECRET
export BOSH_ENVIRONMENT
export BOSH_CA_CERT
export no_proxy=$no_proxy,$BOSH_ENVIRONMENT

echo "exporting the runtime config to bosh_info/runtime-config"
mkdir -p bosh_info
bosh runtime-config > bosh_info/runtime-config

echo "looking for clamav addon in runtime config"

if bosh int bosh_info/runtime-config --path /addons/name=clamav; then

    echo "removing clamav addon from runtime config"
    # remove it from the runtime config
    bosh int bosh_info/runtime-config -op clamav-pipelines/ops/remove-clamav-addon.yml > bosh_info/runtime-config

    echo "updating runtime config"
    # update bosh
    bosh update-config bosh_info/runtime-config
fi

# get the pivnet resource version of clamav    
target_clamav_version=$(bosh int clamav-addon/metadata.yaml --path /release/version)

echo "target version $target_clamav_version found from pivnet"

# if the named runtime exists
if bosh runtime-config --name=clamav > bosh_info/clamav-runtime-config; then    
    
    # and get the installed version of clamav
    installed_clamav_version=$(bosh int bosh_info/clamav-runtime-config --path /releases/name=clamav/version)

    echo "current version $installed_clamav_version installed"

    # if versions match, exit
    if ["$installed_clamav_version" == "$target_clamav_version"]; then
        echo "target version $target_clamav_version matches installed version $installed_clamav_version. exiting"
        exit 0
    fi

    echo "version mismatch. upgrading to $target_clamav_version"
fi

echo "uploading new release of clamav $target_clamav_version to bosh"
# upload the new version of clamav
bosh upload-release clamav-addon/clamav-$target_clamav_version.tgz

echo "generating named runtime config"
# create the interpolated named runtime config 
# overwrite it if it exists because we don't care what version is installed
bosh int clamav-pipelines/runtime.yml \
    -v database_mirror_ip=$DATABASE_MIRROR_IP \
    -v clamav_version=$target_clamav_version \
    > bosh_info/clamav-runtime-config

echo "updating nameed runtime config"
# update the clamav runtime config
bosh --non-interactive update-config \
  --type=runtime \
  --name=clamav \
  bosh_info/clamav-runtime-config

# should we cleanup the old release version? this would be the time
# bosh delete-release clamav/$installed_clamav_version