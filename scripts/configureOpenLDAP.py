#create LDIF file from directory.ini

import sys
import configparser

config = configparser.ConfigParser(strict=False)
config.read('config.ini')

#read global settings
configuration=config['globalsettings']
domain = configuration['domain']
defaultPassword = configuration['defaultPassword']

organizationName=configuration['organization']
organization=''
domainParts=domain.split(".")
organization=domainParts[0]
organizationSuffix=domainParts[0]

dcName=[]
for domainPart in domainParts:
    dcName.append("dc="+domainPart)
dcName=",".join(dcName)

#create files for certificate generation
domainFile=open("generated_domain.txt","w")
print(domain,file=domainFile)
domainFile.close()
orgFile=open("generated_org.txt","w")
print(organizationName,file=orgFile)
orgFile.close()

#create ENV file for OpenLDAP container
envFile=open("generated.yaml","w")

print("LDAP_ORGANISATION: %s" % organizationName,file=envFile)
print("LDAP_DOMAIN: %s" % domain,file=envFile)
print("LDAP_ADMIN_PASSWORD: %s" % configuration['adminPassword'],file=envFile)
print("LDAP_TLS_VERIFY_CLIENT: try",file=envFile)
print("LDAP_LOG_LEVEL: %s" % configuration['logLevel'],file=envFile)

envFile.close()

#create LDIF

#group sections
groupSections = config.sections()
#remove globalsettings from list
groupSections.remove('globalsettings')

ldifFileName="generated.ldif"
ldifFile=open(ldifFileName,"w")

#write to LDIF file, if emptyLine is true, add also empty line
def ldif(line,emptyLine=False):
    print(line,file=ldifFile)
    if emptyLine == True:
        print("",file=ldifFile)

ldif("""# Generated LDIF file

# root entry
#  dn: %s
#  objectClass: dcObject
#  objectClass: organization
#  dc: %s
#  o : %s

# users, as organizational unit
dn: ou=users,%s
objectClass: organizationalUnit
ou: users

# groups, as organizational unit
dn: ou=groups,%s
objectClass: organizationalUnit
ou: groups

""" % (dcName, organization, organization, dcName, dcName))

def getUID(user):
    name=user.split()
    uid=""
    if len(name) == 1:
        uid=name[0]
    else:
        uid=name[0][0]+name[1]
    #replace non ascii characters
    uid = uid.replace("ö","o")
    uid = uid.replace("ä","a")
    uid = uid.replace("å","a")
    uid = uid.replace("ü","u")
    return uid

def getDN(uid):
    return "uid=%s,ou=users,%s" % (uid,dcName)

import random
numbers = "0123456789"
letters = "eyuioaqwrtplkjhgfdszxcvbnm"
def getRandomPassword():
    return ''.join(random.choice(letters) for i in range(8)) + ''.join(random.choice(numbers) for i in range(2))

#add users to LDIF
users=[]
for group in groupSections:
    cfg=config[group]
    for user in config.options(group):
        if user in users:
            break
        pwd=cfg[user]
        if pwd == "":
            if defaultPassword == "RANDOM":
                pwd = getRandomPassword()
            else:
                pwd = defaultPassword
        name=user.split()
        cn=user.title()
        uid=getUID(user)
        sn=""
        if len(name) == 1:
            sn=name[0].title()
        else:
            sn=name[1].title()
        mail="%s@%s" % (uid, domain)
        ldif("""# user: %s
dn: %s
objectClass: inetOrgPerson
cn: %s
sn: %s
uid: %s
mail: %s
userPassword: %s
""" % (cn, getDN(uid), cn, sn, uid, mail, pwd))
        users.append(user)

#add groups to LDIF
for groupName in groupSections:
    ldif("# group: " + groupName)
    ldif("dn: cn=%s,ou=groups,%s" % (groupName,dcName))
    ldif("objectClass: groupOfUniqueNames")
    ldif("cn: " + groupName)
    #users in group
    for user in config.options(groupName):
        ldif("uniqueMember: " + getDN(getUID(user)))
    ldif("")

ldifFile.close()