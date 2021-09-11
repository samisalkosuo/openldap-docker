#Create OpenLDAP image using directory.ini
#build phase uses Python image to create LDIF file
FROM python:3.9.7-alpine3.14 as build

#create LDIF file from ini-file
COPY scripts/createLDIF.py .
COPY directory.ini .
RUN python createLDIF.py

FROM osixia/openldap:1.5.0

ENV LDAP_ORGANISATION "The Far Away Galaxy"
ENV LDAP_DOMAIN "farawaygalaxy.net" 
ENV LDAP_ADMIN_PASSWORD "passw0rd"

COPY --from=build /generated.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/
