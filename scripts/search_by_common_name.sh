#!/bin/bash

function error
{
  echo "[ERROR] $1 is missing."
  echo "Usage: $0 <$1>"
  exit 1

}

if [[ "$1" == "" ]]; then
  error "common name"
fi

source $(pwd)/variables.env

ldapsearch -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PWD -b $LDAP_BASEDN "(&(objectclass=inetOrgPerson)(cn=$1))"
