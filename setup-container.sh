#!/bin/bash
# entrypoint.sh - OpenLDAP container entrypoint
# Bootstraps slapd configuration and data, then starts slapd in the foreground.

set -e

# ── Environment variable defaults ────────────────────────────────────────────
LDAP_DOMAIN="${LDAP_DOMAIN:-sirius.com}"
LDAP_ROOT="${LDAP_ROOT:-dc=sirius,dc=com}"
LDAP_ORGANIZATION="${LDAP_ORGANIZATION:-Sirius Cybernetics Corporation}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-passw0rd}"
DEFAULT_USER_PASSWORD="${DEFAULT_USER_PASSWORD:-passw0rd}"
LDAP_USERS_AND_GROUPS="${LDAP_USERS_AND_GROUPS:-admin:Kiara Doyle,Zac Fraser,Andre Shaw,Daniella Wells;research:Olivia Berry,Oscar Davis,Amelia Lawson,Jonah Stone;operations:Tom Foster,Cara Hawkins,Natalia Matthews,George Watts;marketing:Hilary Banks=hilary,Mallory Keaton=mkeaton,Ed Norton=pwd,Michael Scott=scott}"
LDAP_LOGLEVEL="${LDAP_LOGLEVEL:-256}"
LDAP_PERSIST="${LDAP_PERSIST:-}"
CREATE_CERTS="${CREATE_CERTS:-}"
SANS="${SANS:-}"
IP_SANS="${IP_SANS:-}"

SLAPD_CONFIG_DIR=/etc/openldap/slapd.d
SLAPD_DATA_DIR=/var/lib/openldap/data
SLAPD_CONF_TEMPLATE=/etc/openldap/slapd.conf.tmpl
SLAPD_CONF=/tmp/slapd.conf
GENERATED_LDIF=/ldifs/generated.ldif
OVERLAYS_LDIF=/schemas/overlays.ldif

# ── Step 1: Certificates ─────────────────────────────────────────────────────
echo "==> Checking certificates..."
bash /certs/prepare-certs.sh

# ── Step 2: Generate LDIF from environment variables ─────────────────────────
echo "==> Generating LDIF..."

mkdir -p /ldifs /tmp/users

# Helper: generate a single user entry to a temp file
generate_user_entry() {
  local uid=$1
  local given_name=$2
  local sn=$3
  local password=$4

  cat <<EOF
# user: ${given_name} ${sn}
dn: uid=${uid},ou=users,${LDAP_ROOT}
objectClass: inetOrgPerson
cn: ${given_name} ${sn}
givenName: ${given_name}
sn: ${sn}
uid: ${uid}
mail: ${uid}@${LDAP_DOMAIN}
userPassword: ${password}

EOF
}

# Combine base + additional groups
if [ -n "$ADDITIONAL_LDAP_USERS_AND_GROUPS" ]; then
  LDAP_USERS_AND_GROUPS="${LDAP_USERS_AND_GROUPS};${ADDITIONAL_LDAP_USERS_AND_GROUPS}"
fi

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
  echo "# users organizational unit"
  echo "dn: ou=users,${LDAP_ROOT}"
  echo "objectClass: organizationalUnit"
  echo "ou: users"
  echo ""
  echo "# groups organizational unit"
  echo "dn: ou=groups,${LDAP_ROOT}"
  echo "objectClass: organizationalUnit"
  echo "ou: groups"
  echo ""

  # Parse groups and users
  IFS=';' read -r -a groups_arr <<< "$LDAP_USERS_AND_GROUPS"
  for group in "${groups_arr[@]}"; do
    IFS=':' read -r group_name users_str <<< "$group"
    IFS=',' read -r -a user_array <<< "$users_str"

    echo "# group: ${group_name}"
    echo "dn: cn=${group_name},ou=groups,${LDAP_ROOT}"
    echo "objectClass: groupOfUniqueNames"
    echo "cn: ${group_name}"

    for user in "${user_array[@]}"; do
      # trim leading/trailing whitespace
      user="${user#"${user%%[![:space:]]*}"}"
      user="${user%"${user##*[![:space:]]}"}"

      if [[ "$user" == *"="* ]]; then
        IFS='=' read -r name password <<< "$user"
        IFS=' ' read -r given_name sn <<< "$name"
      else
        password="$DEFAULT_USER_PASSWORD"
        IFS=' ' read -r given_name sn <<< "$user"
      fi

      uid=$(echo "${given_name:0:1}${sn}" | tr '[:upper:]' '[:lower:]')
      generate_user_entry "$uid" "$given_name" "$sn" "$password" > "/tmp/users/${uid}.ldif"
      echo "uniqueMember: uid=${uid},ou=users,${LDAP_ROOT}"
    done
    echo ""
  done
} > /tmp/structure.ldif

# Concatenate structure + all user entries into the final LDIF
cat /tmp/structure.ldif /tmp/users/*.ldif > "$GENERATED_LDIF"
echo "==> LDIF generated: ${GENERATED_LDIF}"

# ── Step 3: Bootstrap slapd if needed ────────────────────────────────────────
DATA_EXISTS=false
if [ -f "${SLAPD_DATA_DIR}/id2entry.mdb" ]; then
  DATA_EXISTS=true
fi

if [ "$LDAP_PERSIST" = "true" ] && [ "$DATA_EXISTS" = "true" ]; then
  echo "==> LDAP_PERSIST=true and existing data found - skipping initialisation."
else
  echo "==> Initialising slapd..."

  # Hash admin password
  LDAP_ADMIN_PASSWORD_HASH=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")

  # Substitute placeholders in the slapd.conf template
  sed \
    -e "s|LDAP_ROOT_PLACEHOLDER|${LDAP_ROOT}|g" \
    -e "s|LDAP_ADMIN_PASSWORD_HASH_PLACEHOLDER|${LDAP_ADMIN_PASSWORD_HASH}|g" \
    -e "s|LOGLEVEL_PLACEHOLDER|${LDAP_LOGLEVEL}|g" \
    "$SLAPD_CONF_TEMPLATE" > "$SLAPD_CONF"

  # Ensure runtime directories exist (VOLUME mount may have replaced build-time dirs)
  mkdir -p "$SLAPD_DATA_DIR" "$SLAPD_CONFIG_DIR"

  # Clean out any previous config/data
  rm -rf "${SLAPD_CONFIG_DIR:?}"/* "${SLAPD_DATA_DIR:?}"/*

  # Re-create data dir after the rm -rf (slapadd -f needs it to exist)
  mkdir -p "$SLAPD_DATA_DIR"

  # Load user data directly from slapd.conf (bypasses cn=config; no DB-open during parse)
  echo "==> Loading user data LDIF..."
  slapadd -v -f "$SLAPD_CONF" -l "$GENERATED_LDIF"
  echo "==> User data loaded."

  # Now convert to cn=config — DB files exist so slaptest opens them cleanly
  echo "==> Converting to cn=config..."
  slaptest -f "$SLAPD_CONF" -F "$SLAPD_CONFIG_DIR"
  echo "==> slapd.d config created."

  # Load overlays into cn=config (database 0 = config backend)
  echo "==> Loading overlays LDIF..."
  slapadd -v -F "$SLAPD_CONFIG_DIR" -n 0 -l "$OVERLAYS_LDIF"
  echo "==> Overlays loaded."
fi

# ── Step 4: Start slapd ───────────────────────────────────────────────────────
echo "==> Starting slapd on ldap://:1389 ldaps://:1636 ..."
exec slapd -F "$SLAPD_CONFIG_DIR" \
           -h "ldap://:1389 ldaps://:1636" \
           -d "$LDAP_LOGLEVEL"
