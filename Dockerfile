#Create OpenLDAP image and configure using config.ini

#create LDIF and configuration
FROM docker.io/python:3.10-alpine3.16 as build

WORKDIR /config
#create environment and LDIF file from ini-file
COPY scripts/configureOpenLDAP.py .
COPY scripts/names.ini .
COPY config.ini .
RUN python configureOpenLDAP.py

#create certificate for OpenLDAP based on domain in config.ini
FROM kazhar/certificate-authority as certbuild

#add custom SANs to certificate
#when building image use --build-arg SANS="san1 san2"
ARG SANS=""

COPY --from=build /config/generated*.txt ./

#generate certificate
RUN DOMAIN=$(cat generated_domain.txt) && \
    ORGANIZATION="$(cat generated_org.txt)" && \
    sh create-certificate.sh -c "$ORGANIZATION" -f ldap openldap.$DOMAIN localhost 127.0.0.1 $SANS

WORKDIR /certs
RUN mv /ca/certificate/ca.crt /ca/ldap.crt /ca/ldap.key .

#OpenLDAP container
FROM docker.io/osixia/openldap:1.5.0

#copy config.ini file
COPY --from=build /config/config.ini /
#copy settings file
COPY --from=build /config/settings.txt /
#copy LDIF file
COPY --from=build /config/generated.ldif /

#copy certs, env and LDIF
COPY --from=certbuild /certs/* /container/service/slapd/assets/certs/
COPY --from=build /config/generated.yaml /container/environment/01-custom/env.yaml
COPY --from=build /config/generated.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/
