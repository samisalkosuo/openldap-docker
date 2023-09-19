#!/bin/bash

if [[ "$1" == "" ]]; then
  echo "Last name is missing."
  exit 1
fi

source $(pwd)/variables.env

ldapsearch -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PWD -b $LDAP_BASEDN "(&(objectclass=inetOrgPerson)(sn=$1))"
