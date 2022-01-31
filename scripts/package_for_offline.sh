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

if [[ ! -f ../config.ini ]]
then
    echo "../config.ini does not exist. Execute this script in openldap-docker/scripts-directory."
    exit 2
fi
set -e

echo "Packaging OpenLDAP demo files..."

__dir_name=openldap-demo
__tmp_dir=/tmp/${__dir_name}
__images_dir=${__tmp_dir}/images
echo "Creating directory ${__tmp_dir}..."
mkdir -p ${__images_dir}

echo "Copying files..."
cp -R ../* ${__tmp_dir}/

echo "Pulling images..."
cat ../Dockerfile |grep ^FROM | uniq |awk -v cmd="${__cmd}"  '{print cmd " pull "  $2}' |sh
echo "Saving images..."
cat ../Dockerfile |grep ^FROM | uniq |awk -v cmd="${__cmd}" -v dir="${__images_dir}" '{print cmd " save -o " dir "/image_" NR ".tar " $2}' | sh

echo "Tarring..."
__tar_file=${__dir_name}.tar
cdir=$(pwd)
cd ${__tmp_dir}
cd ..
tar -cf ${__tar_file} ${__dir_name}/
mv ${__tar_file} $cdir
cd $cdir
rm -rf ${__tmp_dir}
echo "Tar file: ${__tar_file}"
echo "Packaging OpenLDAP demo files...done."
