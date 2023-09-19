#!/bin/bash

function error
{
  echo "[ERROR] $1 is missing."
  echo "Usage: $0 <uid> <groupname>"
  exit 1

}

if [[ "$1" == "" ]]; then
  error "uid"
fi

if [[ "$2" == "" ]]; then
  error "group name"
fi
USER_UID=$1
GROUPNAME=$2

LDIF_FILE=user-to-group.ldif
cat > $LDIF_FILE << EOF
dn: cn=$GROUPNAME,ou=groups,dc=sirius,dc=com
changetype: modify
add: uniqueMember
uniqueMember: uid=$USER_UID,ou=users,dc=sirius,dc=com
EOF

source $(pwd)/variables.env

ldapmodify -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PWD -f $LDIF_FILE
