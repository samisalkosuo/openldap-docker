#!/bin/bash

function error
{
  echo "[ERROR] $1 is missing."
  echo "Usage: $0 <first name> <last name> <password>"
  exit 1

}

if [[ "$1" == "" ]]; then
  error "first name"
fi

if [[ "$2" == "" ]]; then
  error "last name"
fi

if [[ "$3" == "" ]]; then
  error "password"
fi

FIRST_NAME=$1
LAST_NAME=$2
PASSWORD=$3

firstName=$(echo "$FIRST_NAME" | awk '{print tolower($0)}')
lastName=$(echo "$LAST_NAME" | awk '{print tolower($0)}')
firstChar=$(echo $firstName | cut -c1-1)

LDIF_FILE=user.ldif
cat > $LDIF_FILE << EOF
dn: uid=${firstChar}${lastName},ou=users,dc=sirius,dc=com
objectClass: inetOrgPerson
cn: $FIRST_NAME $LAST_NAME
givenName: $FIRST_NAME
sn: $LAST_NAME
uid: ${firstChar}${lastName}
mail: ${firstChar}${lastName}@sirius.com
userPassword: $PASSWORD
EOF

source $(pwd)/variables.env

ldapadd -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PWD -f $LDIF_FILE
