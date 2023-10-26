= OpenLDAP demo container
:toc: left
:toc-title: Table of Contents

OpenLDAP Docker container for demo purposes.

Based on https://hub.docker.com/r/bitnami/openldap/[Bitnami Docker Image for OpenLDAP].

== Use case

Occasionally I have a need to have LDAP server with groups and users. That's why this image exists. No installations, no setup, just run and use.

== Usage

* Get Docker image:
```
docker pull kazhar/openldap-demo
```
* Run Docker image: 
```
docker run -d -p 389:1389 -p 636:1636 --name openldap-demo kazhar/openldap-demo
```
* Login to server:
** Base DN: `dc=sirius,dc=com`
** Admin user: `cn=admin,dc=sirius,dc=com`
** Password: `passw0rd`

Or you can download/clone this repo and create and build your own OpenLDAP image.

== LDAP connection and filters

Some applications ask for LDAP connection and filters. If using the default OpenLDAP demo image, here are the settings and filters that should work.

|===
|Setting |Value

|URL
|`ldap://server.ip:389`

|Base DN
|`dc=sirius,dc=com`

|Bind DN, admin or domain search user
|`cn=admin,dc=sirius,dc=com`

|Admin password
|`passw0rd`

|User filter
|`(&(uid=%v)(objectclass=inetOrgPerson))`

|Group filter
|`(&(cn=%v)(objectclass=groupOfUniqueNames))`

|Group membership search filter
|`(&(uniqueMember={0})(objectclass=groupOfUniqueNames))`

|Group member ID map 
|`groupOfUniqueNames:uniqueMember`

|User ID map
|`*:uid`

|Group ID map
|`*:cn`

|User search base
|`ou=users,dc=sirius,dc=com`

|User search field
|`uid`

|Group search base
|`ou=groups,dc=sirius,dc=com`

|Group search field
|`cn`

|First name
|`givenName`

|Last name
|`sn`

|Email
|`mail`

|Group membership (within inetorgPerson)
|`memberOf`

|Group member field (within groupOfUniqueNames)
|`uniqueMember`


|===

== Groups and users

Groups and users are specified in link:config.ini[config.ini]-file. When building container, LDIF file is generated (much like link:sample.ldif[sample.ldif]).

One group is:

- `cn=admin,ou=groups,dc=sirius,dc=com`

And one user in that group is :

- `uid=kdoyle,ou=users,dc=sirius,dc=com`

The default password for users is `passw0rd`. Another password can be set in link:config.ini[config.ini].

See the generated LDIF or use a LDAP admin tool to get more information about the user entries.

=== Default users and groups

==== Group: admin

|===
|Name |UID |Default password

|Kiara Doyle
|`kdoyle`
|`passw0rd`

|Zac Fraser
|`zfraser`
|`passw0rd`

|Andre Shaw
|`ashaw`
|`passw0rd`

|Daniella Wells
|`dwells`
|`passw0rd`

|===

==== Group: research

|===
|Name|UID |Default password

|Olivia Berry
|`oberry`
|`passw0rd`

|Oscar Davis
|`odavis`
|`passw0rd`

|Amelia Lawson
|`alawson`
|`passw0rd`

|Jonah Stone
|`jstone`
|`passw0rd`

|===

==== Group: operations

|===
|Name|UID |Default password

|Tom Foster
|`tfoster`
|`passw0rd`

|Cara Hawkins
|`chawkins`
|`passw0rd`

|Natalia Matthews
|`nmatthews`
|`passw0rd`

|George Watts
|`gwatts`
|`passw0rd`

|===

==== Group: marketing

|===
|Name|UID |Default password

|Hilary Banks
|`hbanks`
|`hilary`

|Mallory Keaton
|`mkeaton`
|`mkeaton`

|Ed Norton
|`enorton`
|`pwd`

|Michael Scott
|`mscott`
|`scott`

|===

== Create your own demo image

In order to create your own OpenLDAP image with custom domain and users, edit link:config.ini[config.ini] and then build a new OpenLDAP image.

* Edit link:config.ini[config.ini].
* Build image:
```
docker build -t my-openldap .
```
* Start:
```
docker run -it --rm -p 389:1389 -p 636:1636 --name my-openldap my-openldap
```

=== config.ini

link:config.ini[config.ini] include settings like organization name, domain and users/groups. Modify them as required.

link:config.ini[config.ini] includes also key `useRandomOrganizationAndUsers`. If the values is `yes`, random organization and users are created when building the container.

In order to view generated organization and users, the build process adds _config.ini_ and _settings.txt_ files to the root of container filesystem.

* View _settings.txt_, including base DN, bind DN and filters:
```
docker exec my-openldap cat /settings.txt
```
* View _generated.ldif_, including users and passwords:
```
docker exec my-openldap cat /ldifs/generated.ldif
```
* View _config.ini_, used to build the image:
```
docker exec my-openldap cat /config.ini
```

== Certificate

Certificate is created when image is built, using https://github.com/samisalkosuo/certificate-authority[My CA].

SANs in the certificate are:

```
DNS: openldap.<domain in config.ini>
DNS: localhost
IP: 127.0.0.1
```

To add your own SANs, use `--build-arg SANS="san1 san2"` when building the image.

To add your own IP SANs, use `--build-arg IPSANS="ip1 ip2"` when building the image.

If you have existing certificates (for example, Let’s Encrypt certs), add them when starting the container:

```
docker run -d -p 389:1389 -p 636:1636 --name openldap-demo  -v $CERT_DIR:/certs2 -e LDAP_TLS_KEY_FILE=/certs2/privkey1.pem -e LDAP_TLS_CERT_FILE=/certs2/cert1.pem -e LDAP_TLS_CA_FILE=/certs2/chain1.pem kazhar/openldap-demo
```

* _CERT_DIR_ is the directory where certificate files are located. 
* Environment variables tells OpenLDAP the files to use.
* Make note of certificate files permissions in _CERT_DIR_. It may require relaxed permissions, for example 644.

== Scripts

link:scripts/[scripts]-directory includes some scripts that can be used to search LDAP by userid, last name, package files for offline distribution and others.

== OpenShift

* Install openldap-demo to OpenShift:

```
sh ocp-openldap-demo.sh install <namespace>
```

* Uninstall openldap-demo from OpenShift:

```
sh ocp-openldap-demo.sh uninstall <namespace>
```

* See link:ocp-openldap-demo.sh/[ocp-openldap-demo.sh] for details.
* OpenLDAP is accessible within the cluster.
** For example:
** `ldap://openldap-demo.<namespace>.svc.cluster.local:389`
** `ldaps://openldap-demo.<namespace>.svc.cluster.local:636`