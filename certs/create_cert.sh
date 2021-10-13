
#creates certificate for "openldap.<given domain>"
#certificate is signed using CA in this directory

__domain=$1
__organization=$2
__base_name=openldap

__validity_days=3650
__common_name=${__base_name}.${__domain}
__csr_config_file=ldap.csr.txt

  
cat > ${__csr_config_file} << EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
x509_extensions = req_ext
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C=FI
O=${__organization}
emailAddress=mr.smith@${__domain}
CN = ${__common_name}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${__base_name}
DNS.2 = ${__common_name}
DNS.3 = ${__common_name}.local
EOF

#create registry certificate key
openssl genrsa -out ldap.key 4096

#create CSR
openssl req -new -sha256 -key ldap.key -out ldap.csr -config ${__csr_config_file}
  
#sign CSR usign CA cert
openssl x509 -req \
            -extfile ${__csr_config_file} \
            -extensions req_ext \
            -in ldap.csr \
            -CA ca.crt \
            -CAkey ca.key  \
            -CAcreateserial \
            -out ldap.crt \
            -days ${__validity_days} \
            -sha256 
