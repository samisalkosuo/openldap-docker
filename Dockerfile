FROM osixia/openldap:1.2.1

ENV LDAP_ORGANISATION "The Far Away Galaxy"
ENV LDAP_DOMAIN "farawaygalaxy.net" 
ENV LDAP_ADMIN_PASSWORD "passw0rd"

COPY ldif/usersandgroups_posix.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/
