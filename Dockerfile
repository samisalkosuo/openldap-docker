FROM osixia/openldap:1.5.0

ENV LDAP_ORGANISATION "The Far Away Galaxy"
ENV LDAP_DOMAIN "farawaygalaxy.net" 
ENV LDAP_ADMIN_PASSWORD "passw0rd"
ENV LDAP_TLS false

COPY ldif/usersandgroups_posix.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/
