#create LDIF file from config.ini

import configparser
import random

config = configparser.ConfigParser(strict=False)
config.read('config.ini')

#read global settings
configuration=config['globalsettings']

useRandomOrganizations=configuration['useRandomOrganizationAndUsers']
if useRandomOrganizations == "yes":
    #generate random organization like "Stark Entertainment", domain will be stark-entertainment.com
    #and generate random users
    originalAdminPassword = configuration['adminPassword']
    originalDefaultPassword = configuration['defaultPassword']
    originalLogLevel = configuration['logLevel']

    nameconfig = configparser.ConfigParser(strict=False)
    nameconfig.read('names.ini')
    keys=[]
    for key in nameconfig['companynames']:
        keys.append(key.capitalize())
    companyName=random.choice(keys)
    keys=[]
    for key in nameconfig['companysuffix']:
        keys.append(key.capitalize())
    firstNames=[]
    for key in nameconfig['firstnames']:
        firstNames.append(key.capitalize())
    lastNames=[]
    for key in nameconfig['lastnames']:
        lastNames.append(key.capitalize())
    randomNames=[]
    for i in range(16):
        name = "%s %s" % (random.choice(firstNames),random.choice(lastNames))
        if name not in randomNames:
            randomNames.append(name)
    companySuffix=random.choice(keys)
    newconfig = configparser.ConfigParser()
    newconfig.optionxform = str
    newconfig['globalsettings'] = {'useRandomOrganizationAndUsers': 'no',
                      'adminPassword': originalAdminPassword,
                      'logLevel': originalLogLevel,
                      'defaultPassword': originalDefaultPassword,
                      'domain': "%s-%s.com" % (companyName.lower(),companySuffix.lower()),
                      'organization':"%s %s" % (companyName,companySuffix)
                      }
    def setUsers(group,offset):
        newconfig[group]= {randomNames[0 + offset * 4]: "",
                        randomNames[1 + offset * 4]: "",
                        randomNames[2 + offset * 4]: "",
                        randomNames[3 + offset * 4]: ""
    }
    setUsers('admin',0)
    setUsers('research',1)
    setUsers('operations',2)
    setUsers('marketing',3)

    with open('config.ini', 'w') as configfile:
        newconfig.write(configfile)
    #read new configuration
    config = configparser.ConfigParser(strict=False)
    config.read('config.ini')
    configuration=config['globalsettings']


defaultPassword = configuration['defaultPassword']
adminPassword = configuration['adminPassword']
domain = configuration['domain']
organizationName=configuration['organization']

organization=''
domainParts=domain.split(".")
organization=domainParts[0]
#organizationSuffix=domainParts[1]

#save admin password to file to be used in OpenLDAP container
orgFile=open("adminpassword.txt","w")
print(adminPassword,file=orgFile)
orgFile.close()

dcName=[]
for domainPart in domainParts:
    dcName.append("dc="+domainPart)
dcName=",".join(dcName)

#create settings file that includes LDAP base DN, filters, etc.
settingsFile=open("settings.txt","w")
print(f"""#LDAP connections settings
URL                : ldap://<fqdn.or.ip>:389
Base DN            : {dcName}
Bind DN            : cn=admin,{dcName}
Admin password     : {adminPassword}
User filter        : (&(uid=%%v)(objectclass=inetOrgPerson))
Group filter       : (&(cn=%%v)(objectclass=groupOfUniqueNames))
User ID map        : *:uid
Group ID map       : *:cn
Group member ID map: groupOfUniqueNames:uniqueMember
""",file=settingsFile)
settingsFile.close()

#create files for certificate generation
domainFile=open("generated_domain.txt","w")
print(domain,file=domainFile)
domainFile.close()
orgFile=open("generated_org.txt","w")
print(organizationName,file=orgFile)
orgFile.close()

#create ENV file for OpenLDAP container
envFile=open("generated.env","w")

#LDAP_ADMIN_PASSWORD: {adminPassword}
print(f"""#OpenLDAP environment variables
LDAP_ALLOW_ANON_BINDING=no 
LDAP_ROOT={dcName}
LDAP_ADMIN_PASSWORD_FILE=/etc/adminpassword.txt
LDAP_LOGLEVEL={configuration['logLevel']}
LDAP_ENABLE_TLS=yes
LDAP_TLS_CERT_FILE="${{LDAP_TLS_CERT_FILE:-/certs/ldap.crt}}"
LDAP_TLS_KEY_FILE="${{LDAP_TLS_KEY_FILE:-/certs/ldap.key}}"
LDAP_TLS_CA_FILE="${{LDAP_TLS_CA_FILE:-/certs/ca.crt}}"
""",
   file=envFile)

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

ldif(f"""# Generated LDIF file

# root entry
dn: {dcName}
objectClass: dcObject
objectClass: organization
dc: {organization}
o: {organizationName}

# users, as organizational unit
dn: ou=users,{dcName}
objectClass: organizationalUnit
ou: users

# groups, as organizational unit
dn: ou=groups,{dcName}
objectClass: organizationalUnit
ou: groups

""")

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

numbers = "0123456789"
letters = "eyuioaqwrtplkjhgfdszxcvbnmPOIUYTREWQASDFGHJKLMNBVCXZ"
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
        givenName=name[0].title()
        cn=user.title()
        uid=getUID(user)
        sn=""
        if len(name) == 1:
            sn=name[0].title()
        else:
            sn=name[1].title()
        mail="%s@%s" % (uid, domain)
        ldif(f"""# user: {cn}
dn: {getDN(uid)}
objectClass: inetOrgPerson
cn: {cn}
givenName: {givenName}
sn: {sn}
uid: {uid}
mail: {mail}
userPassword: {pwd}
""")
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
