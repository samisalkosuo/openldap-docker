# OpenLDAP demo container
# Based on Red Hat UBI 9.8 with openldap-servers from EPEL 9

FROM registry.access.redhat.com/ubi9/ubi:9.8

# ── Domain / base DN ─────────────────────────────────────────────────────────
ENV LDAP_DOMAIN=sirius.com
ENV LDAP_ROOT=dc=sirius,dc=com
ENV LDAP_ORGANIZATION="Sirius Cybernetics Corporation"

# ── Credentials ──────────────────────────────────────────────────────────────
ENV LDAP_ADMIN_PASSWORD=passw0rd
ENV DEFAULT_USER_PASSWORD=passw0rd

# ── Default users and groups ─────────────────────────────────────────────────
# Legacy variable (commented out, retained for backward compatibility if passed at runtime):
# ENV LDAP_USERS_AND_GROUPS="admin:Kiara Doyle,Zac Fraser,Andre Shaw,Daniella Wells;research:Olivia Berry,Oscar Davis,Amelia Lawson,Jonah Stone;operations:Tom Foster,Cara Hawkins,Natalia Matthews,George Watts;marketing:Hilary Banks=hilary,Mallory Keaton=mkeaton,Ed Norton=pwd,Michael Scott=scott"

# Structured group and user configuration
ENV LDAP_GROUPS="admin,research,operations,marketing"
ENV LDAP_USERS_ADMIN="Kiara Doyle,Zac Fraser,Andre Shaw,Daniella Wells"
ENV LDAP_USERS_RESEARCH="Olivia Berry,Oscar Davis,Amelia Lawson,Jonah Stone"
ENV LDAP_USERS_OPERATIONS="Tom Foster,Cara Hawkins,Natalia Matthews,George Watts"
ENV LDAP_USERS_MARKETING="Hilary Banks=hilary,Mallory Keaton=mkeaton,Ed Norton=pwd,Michael Scott=scott"

# ── Runtime tuning ───────────────────────────────────────────────────────────
# OpenLDAP log level - see https://www.openldap.org/doc/admin24/slapdconf2.html
ENV LDAP_LOGLEVEL=256

# ── TLS certificate paths ─────────────────────────────────────────────────────
ENV LDAP_TLS_CERT_FILE=/certs/ldap.crt
ENV LDAP_TLS_KEY_FILE=/certs/ldap.key
ENV LDAP_TLS_CA_FILE=/certs/ca.crt

# ── Persistence (set to "true" to skip re-init when data directory is not empty) ──
ENV LDAP_PERSIST=

# ── HTTP Browser Service (disabled by default) ────────────────────────────────
ENV ENABLE_HTTP_SERVICE=false
ENV HTTP_PORT=8080

# ── Install EPEL 9, openldap-servers, clients and python3 ────────────────────
RUN dnf install -y \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    dnf install -y \
        openldap-servers \
        openldap-clients \
        python3 \
        openssl && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# ── Prepare directory structure ───────────────────────────────────────────────
RUN mkdir -p \
        /certs \
        /ldifs \
        /schemas \
        /scripts \
        /var/lib/openldap/data \
        /etc/openldap/slapd.d && \
    # OpenShift runs containers with arbitrary UIDs that belong to GID 0.
    # chmod g=u ensures those UIDs can write to the same paths as the owner.
    chown -R 1001:0 \
        /certs \
        /ldifs \
        /schemas \
        /scripts \
        /var/lib/openldap \
        /etc/openldap && \
    chmod -R g=u \
        /certs \
        /ldifs \
        /schemas \
        /scripts \
        /var/lib/openldap \
        /etc/openldap

# ── Copy cert tooling and build-time cert generation ─────────────────────────
COPY certs/ /certs/

USER root
RUN bash /certs/prepare-certs.sh && \
    mv /tmp/certificate.crt /certs/ldap.crt && \
    mv /tmp/certificate.key /certs/ldap.key && \
    mv /tmp/ca.crt          /certs/ca.crt   && \
    rm -f /tmp/*.txt /tmp/*.csr /tmp/*.crt /tmp/*.key && \
    chown 1001:0 /certs/ldap.crt /certs/ldap.key /certs/ca.crt && \
    chmod g=u    /certs/ldap.crt /certs/ldap.key /certs/ca.crt

# ── Copy config files ─────────────────────────────────────────────────────────
# slapd.conf template (substituted at runtime by entrypoint)
COPY config/slapd.conf /etc/openldap/slapd.conf.tmpl
# overlays LDIF (loaded into cn=config at runtime)
COPY config/overlays.ldif /schemas/overlays.ldif

RUN chown 1001:0 /etc/openldap/slapd.conf.tmpl /schemas/overlays.ldif && \
    chmod g=u    /etc/openldap/slapd.conf.tmpl /schemas/overlays.ldif

# ── Copy CLI scripts and tool ────────────────────────────────────────────────
COPY scripts/ /scripts/
RUN chmod -R +x /scripts && \
    ln -sf /scripts/ldap_tool.py /usr/local/bin/ldap-tool && \
    ln -sf /scripts/ldap_tool.py /usr/local/bin/ldap_tool.py && \
    chown -R 1001:0 /scripts && \
    chmod -R g=u /scripts

# ── Copy and wire up the entrypoint ──────────────────────────────────────────
COPY setup-container.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── Runtime user ─────────────────────────────────────────────────────────────
USER 1001

# ── Ports ─────────────────────────────────────────────────────────────────────
EXPOSE 1389 1636 8080

# ── Volume for optional persistence ───────────────────────────────────────────
VOLUME /var/lib/openldap/data

ENTRYPOINT ["/entrypoint.sh"]
