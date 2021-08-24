#!/bin/bash

if [[ "$1" == "" ]]; then
  echo "First name is missing."
  exit 1
fi

if [[ "$2" == "" ]]; then
  echo "Last name is missing."
  exit 1
fi

source $(pwd)/variables.env

ldapsearch -D $LDAP_BIND_DN -w $LDAP_BIND_PWD -p $LDAP_PORT -h $LDAP_SERVER -b $LDAP_BASEDN "(&(objectclass=posixAccount)(givenName=$1)(sn=$2))"
