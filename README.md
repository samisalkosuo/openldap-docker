# openldap-docker

Quick and dirty OpenLDAP Docker container for demo purposes.

Based on [osixia/docker-openldap](https://github.com/osixia/docker-openldap).

## Use case

Occasionally I have a need to have LDAP server with groups and users. That's why this image exists. No installations, no setup, just run and use.

## Usage

- Get Docker image: ```docker pull kazhar/openldap-demo```
- Run Docker image: ```docker run -d -p 389:389 kazhar/openldap-demo```
- Login to server:
  - Base DN: ```dc=farawaygalaxy,dc=net```
  - Admin user: ```cn=admin,dc=farawaygalaxy,dc=net```
  - Password: ```passw0rd```

Or you can download/clone this repo and create and build your own image.

## Groups and users

There are two groups and two users for both groups (easy to add more later).

Groups:

- ```cn=rebels,ou=groups,dc=farawaygalaxy,dc=net```
- ```cn=jedi,ou=groups,dc=farawaygalaxy,dc=net```

Users:

- ```cn=Sabine Wren,ou=users,dc=farawaygalaxy,dc=net```
- ```cn=Jyn Erso,ou=users,dc=farawaygalaxy,dc=net```
- ```cn=Aayla Secura,ou=users,dc=farawaygalaxy,dc=net```
- ```cn=Luminara Unduli,ou=users,dc=farawaygalaxy,dc=net```

See LDIF or use a LDAP admin tool to get more information about the user entries.

## LDIF

[This is the LDIF included in the image](usersandgroups.ldif).



