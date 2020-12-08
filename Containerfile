#Create OpenLDAP image using directory.ini
#build phase uses Python image to create LDIF file
FROM python:3.9.1-alpine3.12 as build

COPY scripts/createLDIFAndDockerfile.py .
COPY directory.ini .
RUN python createLDIFAndDockerfile.py

#CMD ["/bin/sh"]

FROM osixia/openldap:1.4.0

ENV LDAP_ORGANISATION "The Far Away Galaxy"
ENV LDAP_DOMAIN "farawaygalaxy.net" 
ENV LDAP_ADMIN_PASSWORD "passw0rd"
ENV LDAP_TLS false

COPY --from=build /generated.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/

