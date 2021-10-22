#Create OpenLDAP image and configure using config.ini

#create LDIF and configuration
FROM docker.io/python:3.9.7-alpine3.14 as build

WORKDIR /config
#create environment and LDIF file from ini-file
COPY scripts/configureOpenLDAP.py .
COPY config.ini .
RUN python configureOpenLDAP.py

#create certificate for OpenLDAP based on domain in config.ini
FROM docker.io/alpine/openssl as certbuild

WORKDIR /cert

COPY --from=build /config/generated*.txt ./
COPY certs/* ./
RUN DOMAIN=$(cat generated_domain.txt) && ORGANIZATION="$(cat generated_org.txt)"  && sh create_cert.sh $DOMAIN "$ORGANIZATION"

WORKDIR /dist

RUN mv /cert/ca.crt /cert/ldap.crt /cert/ldap.key .

#OpenLDAP container
FROM docker.io/osixia/openldap:1.5.0

COPY --from=certbuild /dist/* /container/service/slapd/assets/certs/
COPY --from=build /config/generated.yaml /container/environment/01-custom/env.yaml
COPY --from=build /config/generated.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/
