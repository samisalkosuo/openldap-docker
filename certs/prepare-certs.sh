#!/bin/bash

FILE=/certs/ca.crt
CA_CRT_EXISTS=false
if [ -f $FILE ]; then
   CA_CRT_EXISTS=true
fi

FILE=/certs/ldap.crt
LDAP_CRT_EXISTS=false
if [ -f $FILE ]; then
   LDAP_CRT_EXISTS=true
fi

FILE=/certs/ldap.key
LDAP_KEY_EXISTS=false
if [ -f $FILE ]; then
   LDAP_KEY_EXISTS=true
fi

#check if any cert files exist using OR
SOME_FILES_EXISTS=false
if [ "$LDAP_CRT_EXISTS" == "true" ] || [ "$LDAP_KEY_EXISTS" == "true" ] || [ "$CA_CRT_EXISTS" == "true" ]
then
  SOME_FILES_EXISTS=true
fi

#check if all cert files exist using AND
ALL_FILES_EXISTS=false
if [ "$LDAP_CRT_EXISTS" == "true" ] && [ "$LDAP_KEY_EXISTS" == "true" ] && [ "$CA_CRT_EXISTS" == "true" ]
then
  ALL_FILES_EXISTS=true
fi

if [ "$ALL_FILES_EXISTS" == "false" ] && [ "$SOME_FILES_EXISTS" == "true" ] 
then
  echo One or more certificate files are missing. Add existing ca.crt, ldap.crt and ldap.key files to certs-directory.
  echo In order to generate certificate, delete existing ca.crt, ldap.crt and ldap.key files from certs-directory.
  exit 1
fi

#generate certificate
if [ "$CREATE_CERTS" == "true" ]
then
  ALL_FILES_EXISTS=false
fi

#generate certificate
if [ "$ALL_FILES_EXISTS" == "false" ]
then
    #create certificates as /tmp/certificate.crt and /tmp/certificate.key
    bash /certs/create-cert.sh -c "$LDAP_ORGANIZATION" -I "127.0.0.1 ${IP_SANS}" openldap.$LDAP_DOMAIN localhost $SANS
    #copy CA and files
    bash /certs/create-cert.sh -C > /tmp/ca.crt
    
    if [ "$CREATE_CERTS" == "true" ]
    then
      mv /tmp/certificate.crt /certs/ldap.crt
      mv /tmp/certificate.key /certs/ldap.key
      mv /tmp/ca.crt /certs/ca.crt
    fi


else
    echo "Using existing certificate."
fi

