#Create OpenLDAP image

#based on bitnami image https://hub.docker.com/r/bitnami/openldap
FROM docker.io/bitnami/openldap:2.6.8

#domain to be used in LDIF
ENV LDAP_DOMAIN sirius.com
#base dn, mandatory, must reflect domain
ENV LDAP_ROOT dc=sirius,dc=com
#organization name/description, could be company name
ENV LDAP_ORGANIZATION "Sirius Cybernetics Corporation"
#admin user password, user name is 'admin'
ENV LDAP_ADMIN_PASSWORD passw0rd
#default password for all users
ENV DEFAULT_USER_PASSWORD passw0rd
ENV LDAP_USERS_AND_GROUPS "admin:Kiara Doyle,Zac Fraser,Andre Shaw,Daniella Wells;research:Olivia Berry,Oscar Davis,Amelia Lawson,Jonah Stone;operations:Tom Foster,Cara Hawkins,Natalia Matthews,George Watts;marketing:Hilary Banks=hilary,Mallory Keaton=mkeaton,Ed Norton=pwd,Michael Scott=scott"

ENV LDAP_ALLOW_ANON_BINDING no
#OpenLDAP log level
#see https://www.openldap.org/doc/admin24/slapdconf2.html for levels
ENV LDAP_LOGLEVEL 256
#default port numbers
ENV LDAP_PORT_NUMBER=1389
ENV LDAP_LDAPS_PORT_NUMBER=1636

#TLS config
ENV LDAP_ENABLE_TLS yes
ENV LDAP_TLS_CERT_FILE /certs/ldap.crt
ENV LDAP_TLS_KEY_FILE  /certs/ldap.key
ENV LDAP_TLS_CA_FILE /certs/ca.crt

#copy OpenLDAP config LDIF
COPY config/overlays.ldif /schemas/

USER root

COPY certs/ /certs/
RUN bash /certs/prepare-certs.sh && \
    mv /tmp/certificate.crt /certs/ldap.crt && \
    mv /tmp/certificate.key /certs/ldap.key && \
    mv /tmp/ca.crt /certs/ca.crt && \
    rm -f /tmp/*.txt /tmp/*.csr /tmp/*.crt /tmp/*.key && \
    chown -R 1001 /certs/ && \
    chmod 644 /certs/* && \
    chmod -R 755 /schemas/

WORKDIR /

#copy setup script
COPY setup-container.sh ./
#create dirs, copy certs and add setup script to container entrypoint script
RUN mkdir -p /ldifs && \
    chown -R 1001 /ldifs/ && \
    cp /opt/bitnami/scripts/openldap/entrypoint.sh tmpentrypoint.sh && \
    cat setup-container.sh tmpentrypoint.sh > /opt/bitnami/scripts/openldap/entrypoint.sh

USER 1001
