#!/bin/bash

#create certificate using CA

# defaults
FILE_NAME=/tmp/certificate
PRINT_CERTS=false
PRINT_BASE64_CERTS=false
VIEW_CERT=false
VALIDITY_DAYS=1000
TMP_CA_FILENAME=tmp_CA
TMP_CA_CRT_FILE=/tmp/${TMP_CA_FILENAME}.crt
TMP_CA_KEY_FILE=/tmp/${TMP_CA_FILENAME}.key
TMP_CA_SRL_FILE=/tmp/${TMP_CA_FILENAME}.srl

COMMAND=create

function Help()
{
    echo "Create certificates using CA."
    echo ""
    echo "Usage: $0 -c <CN> [-f <filename>] [<options>] <DNS SAN> [<DNS SAN> ...]"
    echo ""
    echo "Options:"
    echo " -h                   - This help."
    echo " -c                   - Certificate Common Name (CN)."
    echo " -C                   - Print CA certificate to system out."
    echo " -d                   - Validity days, default 1000."
    echo " -f <filename>        - Filename, without extension, for the certificate and key (default: $FILE_NAME)."
    echo " -I \"IP1 [IP2 ...]\" - IP addresses to add as IP SAN."
    echo " -p                   - Print key and certificate files to system out."
    echo " -P                   - Print base64 encoded key and certificate to system out."
    echo " -v                   - View the certificate in the given file."
    echo ""
    echo "Note: SAN=Subject Alternative Name"
    exit 1
}

function Error
{
    echo "ERROR: $1"
    exit 1
}

if [[ "$1" == "" ]]; then
    echo "No options or arguments."
    Help
fi

#write CA crt and key to file system
function WriteCAFiles
{
  cat > $TMP_CA_CRT_FILE << EOF
-----BEGIN CERTIFICATE-----
MIIFDjCCAvagAwIBAgIUd/a3MOUafcfcd8mygnJ/0s18/68wDQYJKoZIhvcNAQEL
BQAwLzENMAsGA1UEAwwEU2FtaTELMAkGA1UEBhMCRkkxETAPBgNVBAoMCFNhbGtv
c3VvMCAXDTIzMDIxMzEwMTIxMFoYDzIwNTAwMzEzMTAxMjEwWjAvMQ0wCwYDVQQD
DARTYW1pMQswCQYDVQQGEwJGSTERMA8GA1UECgwIU2Fsa29zdW8wggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQCvaQu+VXKC2Pavg6EMLAPJL+uKdU4xfSZs
e5OjSdvtTCLEjigLaOpPbFGjlPvDj28VztTZDaclNSPvaN3e36MZG1+eIA2Cv8jE
sVaoyV319aUkf22pyrMSts2S3d8g6mHmbQqiiF94apDNGdJt7ovbYGZkrUOmxxQ0
/6oGNN29dB0qtAn2RqEwuICcDPH84RxfPl4RhG1JkJRsyX5XvT9jTBTQnDMrqkyI
DV74iCi0v84rBkD2UrcH/4GDw0prZMh++bZOZuiVnudxFurzpN/Ueb+d5+sYIFh9
XXRjeZOamIpPbXj5SR8zEKdGlfTdK+F2rbZo9K5JSNMOmQ4MDqUZekNZ/HV4H09P
lG3if8msJ6luBTtiRLPgAE67TSRQta85wvyjhBInOdaPunewXrLM92kSpdP6ffLS
aIVptm0IzbQWX2ChOw8bH+XOIPdNkDw2wjK9nzVeagcxFCfUaGOXf+t4mH9eKWKw
//mkEcgtNq1dX8R93k4eYVi2ysTks+hX9+DbjyPVPTJmtsihaI+07IK2heun5ypN
hau+JqtRGYvKgrQVnvqWQ70q+vQHfYTBYTkoWpy1cuiQ+qlBebdvMJ/0tfvEHWuD
7JMoVoKOr0OyT385fwXxGyHO6RN/qI8lM4NvMtzi2zgsBOdTFL7DOcerB+xwrzC8
nfs04dhfRQIDAQABoyAwHjAPBgNVHRMBAf8EBTADAQH/MAsGA1UdDwQEAwIBhjAN
BgkqhkiG9w0BAQsFAAOCAgEAN+gfzqmGZxPsAAwRn4J4nR3nfNqA5DADm2sZChrG
EhEFwI/JRdimk+EMDkEb9wE3PLyctLf81Lw8QR1gpSUk+8iDf42H19SqFQFRhkwZ
Ic9+svFyfj+eRDbjpmTBRhqbFcK1TbwGqRQ4YmlIbFFRjT3zK6BLbSrJZqWBFDBj
Z0SZSwB2huPmR6UpIloQYmfzTI3mV6xQIDrhEOau1T37T9H0ZVu16d7T3wggo0aT
oU6KHMFDcMiOvtnH9FP8RPMOQ+48q6CuhySMH1rfOhWfjPjBMo+BzV9NrsQJ+8/0
U3XJKAzNWK/TaWt2IMFhZM6kXkKz0+ZtPeGpGchIxbLg9Gh/LfF+Godofe1FHz8l
misxmmM2pIho+zeF7u7M6SwhYFrbW/XM7GpnS1Pb3sPe999SEp3XcG/TSdwpiro+
G0BrNuddeTIc6FrZWmB2/MdyIGYefuaZ2ZWDaGsPOXWF0jE5SJseM1s72m6B7Wnh
YK2Be+iUTUWC2DsXIugrGuDPSSXj4uhD4Ik91dGCKTnaI7Ub1GEi81fIDNI4onK8
M2UmZnKo7sJI4dTpYSM6A9bpXzr3DD/2QZ6oO4WLH1jOcakDeMDeIdiLDJdk850A
XDRhfXaCYNWflqT/idQteX9TXRCKPnUSsfbaaToYKSIA5meWPxBBJpb+GrTwrcuq
MP0=
-----END CERTIFICATE-----
EOF

  cat > $TMP_CA_KEY_FILE << EOF
-----BEGIN PRIVATE KEY-----
MIIJRAIBADANBgkqhkiG9w0BAQEFAASCCS4wggkqAgEAAoICAQCvaQu+VXKC2Pav
g6EMLAPJL+uKdU4xfSZse5OjSdvtTCLEjigLaOpPbFGjlPvDj28VztTZDaclNSPv
aN3e36MZG1+eIA2Cv8jEsVaoyV319aUkf22pyrMSts2S3d8g6mHmbQqiiF94apDN
GdJt7ovbYGZkrUOmxxQ0/6oGNN29dB0qtAn2RqEwuICcDPH84RxfPl4RhG1JkJRs
yX5XvT9jTBTQnDMrqkyIDV74iCi0v84rBkD2UrcH/4GDw0prZMh++bZOZuiVnudx
FurzpN/Ueb+d5+sYIFh9XXRjeZOamIpPbXj5SR8zEKdGlfTdK+F2rbZo9K5JSNMO
mQ4MDqUZekNZ/HV4H09PlG3if8msJ6luBTtiRLPgAE67TSRQta85wvyjhBInOdaP
unewXrLM92kSpdP6ffLSaIVptm0IzbQWX2ChOw8bH+XOIPdNkDw2wjK9nzVeagcx
FCfUaGOXf+t4mH9eKWKw//mkEcgtNq1dX8R93k4eYVi2ysTks+hX9+DbjyPVPTJm
tsihaI+07IK2heun5ypNhau+JqtRGYvKgrQVnvqWQ70q+vQHfYTBYTkoWpy1cuiQ
+qlBebdvMJ/0tfvEHWuD7JMoVoKOr0OyT385fwXxGyHO6RN/qI8lM4NvMtzi2zgs
BOdTFL7DOcerB+xwrzC8nfs04dhfRQIDAQABAoICAQCSxY3K/ApuDAcVw0kdOzML
w6oN16vO4w4klZ5qciGwxBUPbHd7XJU6UcNZ4g5rivgDQmZ9G9xw2K8x4whLNctt
9aajU+SaM8lVM6H0Z1HUvW8qQ+nJuc7u6MDIlBfgnd2/Bhxw9TUVN+3jgCjATWr+
7AGhWg0SXt+8nPRybwffP2osUitHw7+aWbdbW8Wbt+yakT/63ljnxi87e7nYxoRk
nMOJ7jku3zdcW/vMb3nIC/oBrCDtOzblXVjMnLsHc3QEMwPlRFx23ViBGxELPzj+
u8Sm5uii7mW8uFbr6U2lfN+2KD6iMBoIC3Y8LLuP2Oi1+hJ4bcvrjCD1xQGo+xQP
A6dSgBBU/OLWw/UAjdwi/Ki9YuBUx74rBDPuv3uucdeUYnxgdKpMOC4qCVV95hYf
cNK3fYe1V/fLcWyI3XoiVh1k30qYEysA3TY3JUExFHR9NiIKjB/Ypgivy492+JPR
fxRm8+fYGqFn/Zx2FGn8/gtwHRuz7cK1AytmNbtCv7a5URoMV89LGW9lP9+zKStN
/Hc/9PQXBcERuAkzeNj1CEucgOjbRXfNouVeDa/CmjRSR6wR2/JgUkkH9EvDZNPy
K8AyljYXgJBh9BDv9opFwgEhzoiBnSX3tetfFviELSs9J4M9yxPoc2lsHqkegZ1H
kLZHCMcJ36j5iQVROXPmHQKCAQEA2fLpMxtYRJ9mo3PaKHBOGvgMs/K/MCyozNcX
Dm64rNJIUni01r0/AIfmIqMgu9aln6yRnesGEfKWSO3axQOJcnHPRvvkL/8iHuoX
fwX0NWU3nVliHjkqobktpA1ZxEdniXd3FO1Qi4NMYG2CGfq9xMZ3ijMvoMmcKIgr
1vyTra6CX1MpPrFu9Vcv+6lWxmJHW1IsHe+bg9RGpYpTjlKcHIemI7oOTLZr0yev
OwnjFwnLVOTHCi6u8NZqh/uOVZE4eOT6AXcfQ/G4WvfEdv/qHGslJuoy/jh3sE1g
5cjM16zAHPjwupHYUYu8s20D69zhjqeyzIoZ7W4TNgstbP7x1wKCAQEAzgjmzlpI
bRagEZ+u2ollelmKKIaCOUmJwUUIKkAg4F1ftzgXECOcDDMYPG4nhh8O9vXHZ9SM
xEPt22MYAIAUTf9OIJktObtZScbl+iQS+KgNj8lWSKjItrQQpfTnzAQzbCXuh+da
kp6UOzZio796yfgMdmmwh+jzMB/1oi1PXMyAME6N+xxOQPkJcRT6mqP4sf91wco8
pCH7Riruzt8GtQk8eK8LUhV3rMTHbIKcM1HkIFPLSn/1yGmUGOzwaTPO3camEMRQ
CmfVYS6xAHkAUx5MQqAlEZIyIuYlbWHxEf4I697BwimNahLq1XrTne3SiJpaOcci
sk3ZPjBgf18MQwKCAQBLWQg4C+8TIkx4m7fDHThTaIfzuitQu0/MKVwmOC8OSFCK
eoKCbsCWLWVpeh358nYl4qIhBzx8/fHo2po0XEmrUB9JuhGkaj7gkyt2VZec0hZN
Bra+HiNX784QljD/g3QO+Uco6/ZZlRXVjGZbFu1+VuLC23lOzAR5msIVPBLOC7O0
wupSa0Mh/HdxOJTwVs+2iY0I+Go6RCv8VPsYDAU+c8MDPPJuoO5b/K8+6Ocictdh
zQnmwkbmqioAQv5tJJxyZy7rTMR5V9rVUC0Sutyz4HLipjrk2p6+S7IBHs96jJWK
LqICziML5hRhr4GYjC9Kgz10KxZVmCV6HJkiwmzXAoIBAQCuauq5FcTqVJT9Vmj3
qAi4IsTKudPUG2T6sC3RVqh+R42X1WvwxbR8v2RtA/OBnxlUB4zfYRgprjfV2XWg
Nsz5mn/RKNsYXHmh8zcNIyzMQ7f3WUIqEHiZ8qWFWGZCV+wQSaw8cKZEKOrjlY67
gIW6JLqoI6DF7Xax7txKhoEA1j5OprGbOsMkTa6ohFICR31pchGGFGZxrDLDm+S+
TB+pckA3CjhTLMk7APqx6X/CEjlFBKq8TscK+hXdY/fBl5IwPNKorwfzRyNkOdqt
w8F6m9ODM38t+M1ordxRVPB3gs6anuD4NaT5fzo9rtUmhQYNjl2DPAkrWKvn8Zw/
N39xAoIBAQCF8lyJCFsZ+fE0ptJ8NO3DWMLZ0sBQfwoX66iNMeIoYfnjtSa7zSfX
OZRsjqHy/69TNV9aZsNJw61M3pGwv0C2BHIo20RKqnBo48Fa8FuNp10ggCWjgIVR
+jNEn3aHqxVgYz78R85t8WpsEuo+zFM/K0q/N/Ua8EZwBS+dANRwnjgoSacGsftt
2kMPUzhDmC/CZriL65MDQyd5N4+chQlYYTZjqEwedHA098Gc+oGjvCLS/ka88WUN
WPzYkKhivHDxKNZ4ch8fHh5u2CHMOl5khCSQ5QqGshyDQNyeP2OueQQmBctlck49
ctaKYwzYWdNLWDeGMZF0OK0rZqMhFyDV
-----END PRIVATE KEY-----
EOF
}

#remove CA files from file system
function RemoveCAFiles
{
  rm -f $TMP_CA_CRT_FILE
  rm -f $TMP_CA_KEY_FILE
  rm -f $TMP_CA_SRL_FILE
}



# Get the options
while getopts "I:hf:c:d:PpSvC" option; do
   case $option in
      h) 
        Help;;
      f) 
        FILE_NAME=$OPTARG;;
      c) 
        COMMON_NAME=$OPTARG;;
      d) 
        VALIDITY_DAYS=$OPTARG;;
      p) 
        COMMAND=print_certs
        PRINT_CERTS=true;;
      P) 
        COMMAND=print_base64_certs
        PRINT_BASE64_CERTS=true;;
      v)
        COMMAND=view_cert
        VIEW_CERT=true;;
      C)
        COMMAND=print_ca_cert
        ;;
      I)
        IP_SANS=$OPTARG;;
     \?)
        Error "Unknown option."
   esac
done


function viewCert
{
  openssl x509 -in $FILE_NAME.crt -text -noout
}

function printCert
{
  cat $FILE_NAME.key
  cat $FILE_NAME.crt    
}

function printCACert
{
  WriteCAFiles
  cat $TMP_CA_CRT_FILE    
}

function printCertAsBase64
{
  key=$(cat $FILE_NAME.key | base64 -w 0)
  echo "base64 key: $key"
  echo ""
  cert=$(cat $FILE_NAME.crt | base64 -w 0)
  echo "base64 certificate: $cert"        
}

function createCert
{
  if [[ "$COMMON_NAME" == "" ]]; then
      Error "-c <common name> not specified."
  fi

  echo "Creating self-signed certificate using CA..."
  WriteCAFiles

  __common_name=$COMMON_NAME
  __validity_days=$VALIDITY_DAYS
  __ca_file=$TMP_CA_CRT_FILE
  __ca_key_file=$TMP_CA_KEY_FILE
  __csr_cfg_file=${FILE_NAME}_csr.txt
  __csr_file=${FILE_NAME}.csr
  __cert_file=${FILE_NAME}.crt
  __cert_key_file=${FILE_NAME}.key

  #shift
  __alt_names_array=($*)

  cat > ${__csr_cfg_file} << EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
x509_extensions = req_ext
req_extensions = req_ext
distinguished_name = dn

[ dn ]
commonName = ${__common_name}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
EOF
  #optionally, add fields under dn:
  # organizationName  = IBM
  # organizationalUnitName = Technology
  # localityName = Helsinki
  # stateOrProvinceName = Uusimaa
  # countryName = FI
  # emailAddress = sami.salkosuo@noreply.com

  position=0
  for ((i = 0; i < ${#__alt_names_array[@]}; ++i)); do
      # bash arrays are 0-indexed
      position=$(( $position + 1 ))
      name=${__alt_names_array[$i]}
      echo "DNS.$position  = $name" >> ${__csr_cfg_file}
  done

  #add IP SANs
  __alt_names_array=($IP_SANS)
  position=0
  for ((i = 0; i < ${#__alt_names_array[@]}; i++)); do
      # bash arrays are 0-indexed
      position=$(( $position + 1 ))
      name=${__alt_names_array[$i]}
      echo "IP.$position  = $name" >> ${__csr_cfg_file}
  done


  #create certificate key:
  openssl genrsa -out ${__cert_key_file} 4096

  #create CSR:  
  openssl req -new -sha256 -key ${__cert_key_file} -out ${__csr_file} -config ${__csr_cfg_file}

  #sign CSR usign CA cert
  openssl x509 -req \
          -extfile ${__csr_cfg_file} \
          -extensions req_ext \
          -in ${__csr_file} \
          -CA ${__ca_file} \
          -CAkey ${__ca_key_file} \
          -CAcreateserial \
          -out ${__cert_file} \
          -days ${__validity_days} \
          -sha256

  #delete temp files
  #rm -f $__csr_cfg_file
  #rm -f $__csr_file
  RemoveCAFiles
  echo "Creating self-signed certificate using CA...done." 

}

case "$COMMAND" in
    print_certs)
        printCert
    ;;
    print_ca_cert)
        printCACert
    ;;
    view_cert)
      viewCert
    ;;
    print_base64_certs)
      printCertAsBase64
    ;;
    create)
      #remove options so parameters can be used $1, $2 and so on
      shift $((OPTIND - 1))

      if [[ "$1" == "" ]]; then
          Error "SAN not specified. At least one SAN is required."
      fi

      createCert "$@"
    ;;
    *)
      Help
    ;;
esac
