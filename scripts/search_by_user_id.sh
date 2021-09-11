#!/bin/bash

 
if [[ "$1" == "" ]]; then
  echo "User ID is missing."
  exit 1
fi

source $(pwd)/variables.env

ldapsearch -D $LDAP_BIND_DN -w $LDAP_BIND_PWD -p $LDAP_PORT -h $LDAP_SERVER -b $LDAP_BASEDN "(&(objectclass=inetOrgPerson)(uid=$1))"

