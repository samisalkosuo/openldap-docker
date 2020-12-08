#!/bin/bash

#this script package files and images for offline distribution
#useful when this OpenLDAP demo is needed in an airgapped environment

__cmd=podman
if ! command -v ${__cmd} &> /dev/null
then 
  #podman does not exists, check docker
  __cmd=docker
  if ! command -v ${__cmd} &> /dev/null
  then 
    #podman does not exists, check docker
        echo "Neither 'podman' nor 'docker' could not be found."
        echo "Can not package files or images."
        exit 1
    fi
fi

set -e

echo "Packaging OpenLDAP demo files..."

__tmp_dir=openldap-demo
echo "Creating directory ${__tmp_dir}..."
mkdir -p ${__tmp_dir}/ldif
mkdir -p ${__tmp_dir}/scripts

echo "Copying files..."
cp -R ldif/* ${__tmp_dir}/ldif/
cp -R scripts/* ${__tmp_dir}/scripts/
cp Containerfile Dockerfile directory.ini README* LICENSE ${__tmp_dir}/

echo "Saving images..."
cat Containerfile Dockerfile |grep ^FROM | uniq |awk -v cmd="${__cmd}" -v dir="${__tmp_dir}" '{print cmd " save -o " dir "/image_" NR ".tar " $2}' |sh

echo "Tarring..."
tar -cf ${__tmp_dir}.tar ${__tmp_dir}/
rm -rf ${__tmp_dir}
echo "Tar file: ${__tmp_dir}.tar"
echo "Packaging OpenLDAP demo files...done."
