#!/bin/bash                                                                                                                                                                                                                                                                                                                   # Environment variables                                                                                                                                        LDAP_DOMAIN="sirius.com"                                                                                                                                       LDAP_ROOT="dc=sirius,dc=com"                                                                                                                                   LDAP_ORGANIZATION="Sirius Cybernetics Corporation"                                                                                                             DEFAULT_USER_PASSWORD="passw0rd"                                                                                                                               LDIF="admin:Kiara Doyle,Zac Fraser,Andre Shaw,Daniella Wells;research:Olivia Berry,Oscar Davis,Amelia Lawson,Jonah Stone;operations:Tom Foster,Cara Hawkins,Natalia Matthews,George Watts;marketing:Hilary Banks=hilary,Mallory Keaton=mkeaton,Ed Norton=pwd,Michael Scott=scott"

# Check or create certificates
bash /certs/prepare-certs.sh

# Create LDIF file

LDIF_FILE=/tmp/output.ldif
GENERATED_LDIF_FILE=/ldifs/generated.ldif

# Helper function to generate user entry
generate_user_entry() {
  local uid=$1
  local given_name=$2
  local sn=$3
  local password=$4

  echo "# user: ${given_name} ${sn}"
  echo "dn: uid=${uid},ou=users,${LDAP_ROOT}"
  echo "objectClass: inetOrgPerson"
  echo "cn: ${given_name} ${sn}"
  echo "givenName: ${given_name}"
  echo "sn: ${sn}"
  echo "uid: ${uid}"
  echo "mail: ${uid}@${LDAP_DOMAIN}"
  echo "userPassword: ${password}"
  echo ""
}

# Create the LDIF file
{
  echo "# Generated LDIF file"
  echo ""
  echo "# root entry"
  echo "dn: ${LDAP_ROOT}"
  echo "objectClass: dcObject"
  echo "objectClass: organization"
  echo "dc: ${LDAP_DOMAIN%%.*}"
  echo "o: ${LDAP_ORGANIZATION}"
  echo ""
  echo "# users, as organizational unit"
  echo "dn: ou=users,${LDAP_ROOT}"
  echo "objectClass: organizationalUnit"
  echo "ou: users"
  echo ""
  echo "# groups, as organizational unit"
  echo "dn: ou=groups,${LDAP_ROOT}"
  echo "objectClass: organizationalUnit"
  echo "ou: groups"
  echo ""

  if [ "$ADDITIONAL_LDAP_USERS_AND_GROUPS" != "" ]; then
    LDAP_USERS_AND_GROUPS="$LDAP_USERS_AND_GROUPS;$ADDITIONAL_LDAP_USERS_AND_GROUPS"        
  fi

    # Parse LDIF variable to create user and group entries
  IFS=';' read -r -a groups <<< "$LDAP_USERS_AND_GROUPS"
  for group in "${groups[@]}"; do
    IFS=':' read -r group_name users <<< "$group"
    IFS=',' read -r -a user_array <<< "$users"

    echo "# group: ${group_name}"
    echo "dn: cn=${group_name},ou=groups,${LDAP_ROOT}"
    echo "objectClass: groupOfUniqueNames"
    echo "cn: ${group_name}"

    for user in "${user_array[@]}"; do
      if [[ "$user" == *"="* ]]; then
        IFS='=' read -r name password <<< "$user"
        IFS=' ' read -r given_name sn <<< "$name"
      else
        password=$DEFAULT_USER_PASSWORD
        IFS=' ' read -r given_name sn <<< "$user"
      fi

      uid=$(echo "${given_name:0:1}${sn}" | tr '[:upper:]' '[:lower:]')
      generate_user_entry "$uid" "$given_name" "$sn" "$password" > /tmp/user_$uid.ldif
      echo "uniqueMember: uid=${uid},ou=users,${LDAP_ROOT}"
    done
    echo ""
  done
} > "$LDIF_FILE"

ls -1 /tmp/user_*ldif | awk '{print "cat " $1 " >> /tmp/users.ldif"}' |sh

cat $LDIF_FILE /tmp/users.ldif > $GENERATED_LDIF_FILE

echo "LDIF file has been generated: $GENERATED_LDIF_FILE"

