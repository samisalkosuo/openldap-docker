#!/bin/bash


function help
{
    echo "OpenLDAP demo install/uninstall script."
    echo ""
    echo "Usage: $0 install [<cmd-options>]"
    echo ""
    echo "Commands:"
    echo ""
    echo "  help                   - This help."
    echo "  install <NAMESPACE>    - Install OpenLDAP demo to given namespace."
    echo "  uninstall <NAMESPACE>  - Uninstall OpenLDAP demo from given namespace."
    echo ""
    exit 1
}

function error
{
    echo "ERROR: $1"
    exit 1
}

if [[ "$1" == "" ]]; then
    #echo "No commands."
    help
fi

function namespaceOperation
{
    local OPERATION=$1
    local NAMESPACE=$2
    cat << EOF | oc $OPERATION -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
spec:
  finalizers:
  - kubernetes
EOF

}

function deploymentOperation
{
    local OPERATION=$1
    cat << EOF | oc $OPERATION -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openldap-demo-deployment
  labels:
    app: openldap-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: openldap-demo
  template:
    metadata:
      labels:
        app: openldap-demo
    spec:
      containers:
      - name: openldap
        image: kazhar/openldap-demo:latest
        imagePullPolicy: Always
        securityContext:
          privileged: true
        ports:
        - containerPort: 1389
          name: ldap-port
        - containerPort: 1636
          name: ldaps-port
EOF

    cat << EOF | oc $OPERATION -f -
apiVersion: v1
kind: Service
metadata:
  name: openldap-demo 
  labels:
    app: openldap-demo
spec:
  selector:
    app: openldap-demo
  ports:
    - port: 389
      targetPort: 1389
      name: ldap-port
    - port: 636
      targetPort: 1636
      name: ldaps-port
EOF

}

function installOpenLDAPDemo
{
    local NAMESPACE=$1
    if [ "$NAMESPACE" = "" ]; then
      error "Namespace not given."
    fi
    #create new namespace
    namespaceOperation apply $NAMESPACE
    #change to project
    oc project $NAMESPACE
    
    oc adm policy add-scc-to-user privileged -z default

    deploymentOperation apply

}

function uninstallOpenLDAPDemo
{
    local NAMESPACE=$1
    if [ "$NAMESPACE" = "" ]; then
      error "Namespace not given."
    fi

    deploymentOperation delete

    namespaceOperation delete $NAMESPACE

}

#call functions
#note 'shift' command moves ARGS to the left 

case "$1" in
    install)
      shift
      installOpenLDAPDemo $1
    ;;
    uninstall)
      shift
      uninstallOpenLDAPDemo $1
    ;;    
    help)
        help
    ;;
    *)
        help
    ;;
esac



