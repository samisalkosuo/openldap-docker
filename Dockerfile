#Create OpenLDAP image and configure using config.ini

#create LDIF and configuration
FROM docker.io/python:3.10-alpine3.16 as build

WORKDIR /config
#create environment and LDIF file from ini-file
COPY scripts/configureOpenLDAP.py .
COPY scripts/names.ini .
COPY config.ini .
RUN python configureOpenLDAP.py
#RUN cat generated.ldif

#create certificate for OpenLDAP based on domain in config.ini
FROM kazhar/certificate-authority as certbuild

#add custom SANs to certificate
#when building image use --build-arg SANS="san1 san2"
ARG SANS=""
ARG IP_SANS=""

COPY --from=build /config/generated*.txt ./

#generate certificate
RUN DOMAIN=$(cat generated_domain.txt) && \
    ORGANIZATION="$(cat generated_org.txt)" && \
    sh create-certificate.sh -c "$ORGANIZATION" -I "127.0.0.1 ${IP_SANS}" -f ldap openldap.$DOMAIN localhost $SANS

WORKDIR /certs
RUN mv /ca/certificate/ca.crt /ca/ldap.crt /ca/ldap.key .

#OpenLDAP container
#based on bitnami image https://hub.docker.com/r/bitnami/openldap
FROM docker.io/bitnami/openldap:2.6.4

#default port numbers
#ENV LDAP_PORT_NUMBER=1389
#ENV LDAP_LDAPS_PORT_NUMBER=1636

#copy OpenLDAP config LDIF
COPY config/overlays.ldif /schemas/
#copy certs
COPY --from=certbuild --chmod=644 /certs/* /certs/
#copy config.ini file
COPY --from=build /config/config.ini /
#copy settings file
COPY --from=build /config/settings.txt /
#copy admin password file
COPY --from=build /config/adminpassword.txt /etc/
#copy LDIF file
COPY --from=build /config/generated.ldif /ldifs/
#copy env file
COPY --from=build /config/generated.env /tmp/

#configure libopenldap.sh script to include generate environment variables
#TODO: modify source libopenldap.sh so that it reads environment variables from file 
#before setting the environment
USER root
WORKDIR /opt/bitnami/scripts/
RUN csplit --suppress-matched libopenldap.sh '/ldap_env()/' '{*}' && \
    cat xx00 > new.sh && \
    cat /tmp/generated.env >> new.sh && \
    echo "ldap_env() {" >> new.sh && \
    cat xx01 >> new.sh && \
    cp libopenldap.sh libopenldap.sh.original && \
    cp new.sh libopenldap.sh 
#    && \
#    cat libopenldap.sh
WORKDIR /
USER 1001

#print settings
RUN cat /settings.txt
