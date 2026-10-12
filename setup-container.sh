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
LDAP_LOGLEVEL="${LDAP_LOGLEVEL:-256}"
LDAP_PERSIST="${LDAP_PERSIST:-}"
CREATE_CERTS="${CREATE_CERTS:-}"
SANS="${SANS:-}"
IP_SANS="${IP_SANS:-}"

# Legacy group and user configuration (kept for backward compatibility)
LDAP_USERS_AND_GROUPS="${LDAP_USERS_AND_GROUPS:-}"
ADDITIONAL_LDAP_USERS_AND_GROUPS="${ADDITIONAL_LDAP_USERS_AND_GROUPS:-}"

# Structured group and user configuration
LDAP_GROUPS="${LDAP_GROUPS:-admin,research,operations,marketing}"
LDAP_USERS_ADMIN="${LDAP_USERS_ADMIN:-Kiara Doyle,Zac Fraser,Andre Shaw,Daniella Wells}"
LDAP_USERS_RESEARCH="${LDAP_USERS_RESEARCH:-Olivia Berry,Oscar Davis,Amelia Lawson,Jonah Stone}"
LDAP_USERS_OPERATIONS="${LDAP_USERS_OPERATIONS:-Tom Foster,Cara Hawkins,Natalia Matthews,George Watts}"
LDAP_USERS_MARKETING="${LDAP_USERS_MARKETING:-Hilary Banks=hilary,Mallory Keaton=mkeaton,Ed Norton=pwd,Michael Scott=scott}"
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
  local cn=$4
  local password=$5

  cat <<EOF
# user: ${cn}
dn: uid=${uid},ou=users,${LDAP_ROOT}
objectClass: inetOrgPerson
cn: ${cn}
givenName: ${given_name}
sn: ${sn}
uid: ${uid}
mail: ${uid}@${LDAP_DOMAIN}
userPassword: ${password}

EOF
}

# Helper: parse individual user specification and generate user LDIF
# Supports: "FirstName LastName[=password]" or "uid[=password]"
process_user() {
  local raw_user="$1"
  raw_user="${raw_user#"${raw_user%%[![:space:]]*}"}"
  raw_user="${raw_user%"${raw_user##*[![:space:]]}"}"
  [ -z "$raw_user" ] && return 0

  local name_part=""
  local password=""
  if [[ "$raw_user" == *"="* ]]; then
    IFS='=' read -r name_part password <<< "$raw_user"
  else
    name_part="$raw_user"
    password="$DEFAULT_USER_PASSWORD"
  fi

  name_part="${name_part#"${name_part%%[![:space:]]*}"}"
  name_part="${name_part%"${name_part##*[![:space:]]}"}"
  [ -z "$name_part" ] && return 0

  local uid=""
  local given_name=""
  local sn=""
  local cn=""

  if [[ "$name_part" == *" "* ]]; then
    given_name="${name_part%% *}"
    sn="${name_part#* }"
    local sn_clean="${sn// /}"
    uid=$(echo "${given_name:0:1}${sn_clean}" | tr '[:upper:]' '[:lower:]')
    cn="${name_part}"
  else
    uid=$(echo "$name_part" | tr '[:upper:]' '[:lower:]')
    given_name="User"
    local first_char=$(echo "${uid:0:1}" | tr '[:lower:]' '[:upper:]')
    local rest_chars="${uid:1}"
    sn="${first_char}${rest_chars}"
    cn="${given_name} ${sn}"
  fi

  generate_user_entry "$uid" "$given_name" "$sn" "$cn" "$password" > "/tmp/users/${uid}.ldif"
  echo "$uid"
}

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

  if [ -n "$LDAP_USERS_AND_GROUPS" ] || [ -n "$ADDITIONAL_LDAP_USERS_AND_GROUPS" ]; then
    echo "==> Using legacy LDAP_USERS_AND_GROUPS / ADDITIONAL_LDAP_USERS_AND_GROUPS configuration..." >&2
    LEGACY_DEFAULT="admin:Kiara Doyle,Zac Fraser,Andre Shaw,Daniella Wells;research:Olivia Berry,Oscar Davis,Amelia Lawson,Jonah Stone;operations:Tom Foster,Cara Hawkins,Natalia Matthews,George Watts;marketing:Hilary Banks=hilary,Mallory Keaton=mkeaton,Ed Norton=pwd,Michael Scott=scott"
    LDAP_USERS_AND_GROUPS="${LDAP_USERS_AND_GROUPS:-$LEGACY_DEFAULT}"
    if [ -n "$ADDITIONAL_LDAP_USERS_AND_GROUPS" ]; then
      LDAP_USERS_AND_GROUPS="${LDAP_USERS_AND_GROUPS};${ADDITIONAL_LDAP_USERS_AND_GROUPS}"
    fi

    IFS=';' read -r -a groups_arr <<< "$LDAP_USERS_AND_GROUPS"
    for group in "${groups_arr[@]}"; do
      IFS=':' read -r group_name users_str <<< "$group"
      group_name="${group_name#"${group_name%%[![:space:]]*}"}"
      group_name="${group_name%"${group_name##*[![:space:]]}"}"
      [ -z "$group_name" ] && continue

      echo "# group: ${group_name}"
      echo "dn: cn=${group_name},ou=groups,${LDAP_ROOT}"
      echo "objectClass: groupOfUniqueNames"
      echo "cn: ${group_name}"

      IFS=',' read -r -a user_array <<< "$users_str"
      for user in "${user_array[@]}"; do
        uid=$(process_user "$user")
        [ -n "$uid" ] && echo "uniqueMember: uid=${uid},ou=users,${LDAP_ROOT}"
      done
      echo ""
    done
  else
    echo "==> Using structured LDAP_GROUPS, LDAP_USERS_*, and LDAP_GROUP_* configuration..." >&2
    declare -A groups_map
    groups_order=()

    # 1. Collect groups from LDAP_GROUPS
    if [ -n "$LDAP_GROUPS" ]; then
      IFS=',' read -r -a defined_groups <<< "$LDAP_GROUPS"
      for g in "${defined_groups[@]}"; do
        g="${g#"${g%%[![:space:]]*}"}"
        g="${g%"${g##*[![:space:]]}"}"
        [ -z "$g" ] && continue
        g_lower=$(echo "$g" | tr '[:upper:]' '[:lower:]')
        if [ -z "${groups_map[$g_lower]:-}" ]; then
          groups_order+=("$g_lower")
          groups_map[$g_lower]=1
        fi
      done
    fi

    # 2. Collect ad-hoc groups from LDAP_GROUP_* environment variables
    while IFS= read -r var_name; do
      [ -z "$var_name" ] && continue
      group_suffix="${var_name#LDAP_GROUP_}"
      [ -z "$group_suffix" ] && continue
      g_lower=$(echo "$group_suffix" | tr '[:upper:]' '[:lower:]')
      if [ -z "${groups_map[$g_lower]:-}" ]; then
        groups_order+=("$g_lower")
        groups_map[$g_lower]=1
      fi
    done < <(compgen -v LDAP_GROUP_ 2>/dev/null || env | grep -E '^LDAP_GROUP_[a-zA-Z0-9_]+=' | cut -d= -f1 | sort -u)

    # 3. Process each group and its users
    for g in "${groups_order[@]}"; do
      g_upper=$(echo "$g" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
      var_users="LDAP_USERS_${g_upper}"
      var_group="LDAP_GROUP_${g_upper}"

      users_str_1="${!var_users:-}"
      users_str_2="${!var_group:-}"

      users_str=""
      if [ -n "$users_str_1" ] && [ -n "$users_str_2" ]; then
        users_str="${users_str_1},${users_str_2}"
      elif [ -n "$users_str_1" ]; then
        users_str="$users_str_1"
      else
        users_str="$users_str_2"
      fi

      echo "# group: ${g}"
      echo "dn: cn=${g},ou=groups,${LDAP_ROOT}"
      echo "objectClass: groupOfUniqueNames"
      echo "cn: ${g}"

      declare -A seen_members_in_group
      IFS=',' read -r -a user_array <<< "$users_str"
      for user in "${user_array[@]}"; do
        user="${user#"${user%%[![:space:]]*}"}"
        user="${user%"${user##*[![:space:]]}"}"
        [ -z "$user" ] && continue

        uid=$(process_user "$user")
        if [ -n "$uid" ] && [ -z "${seen_members_in_group[$uid]:-}" ]; then
          echo "uniqueMember: uid=${uid},ou=users,${LDAP_ROOT}"
          seen_members_in_group[$uid]=1
        fi
      done
      unset seen_members_in_group
      echo ""
    done
  fi
} > /tmp/structure.ldif

# Concatenate structure + all user entries into the final LDIF
if compgen -G "/tmp/users/*.ldif" > /dev/null 2>&1; then
  cat /tmp/structure.ldif /tmp/users/*.ldif > "$GENERATED_LDIF"
else
  cat /tmp/structure.ldif > "$GENERATED_LDIF"
fi
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
