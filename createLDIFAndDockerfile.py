#python script to create LDIF and Dockerfile from a directory.ini file

import sys
import configparser

dockerfileName="Dockerfile.created"

#check that Python is 3.6 or later
assert sys.version_info >= (3, 6)

config = configparser.ConfigParser(strict=False)
config.read('directory.ini')

#read global settings
domain = config['globalsettings']['domain']
defaultPassword = config['globalsettings']['defaultPassword']

dcName=[]
for domainPart in domain.split("."):
    dcName.append("dc="+domainPart)
dcName=",".join(dcName)

#user sections
sections = config.sections()
#remove globalsettings from list
sections.remove('globalsettings')

ldifFileName="generated.ldif"
ldifFile=open(ldifFileName,"w")

def ldif(line,emptyLine=False):
    print(line,file=ldifFile)
    if emptyLine == True:
        print("",file=ldifFile)


ldif("#Generated LDIF file",emptyLine=True)

#create ous in LDIF
ldif("#users as organizational unit")
ldif("dn: ou=users,%s" % dcName)
ldif("objectClass: organizationalUnit")
ldif("ou: users",emptyLine=True)
ldif("#groups as organizational unit")
ldif("dn: ou=groups,%s" % dcName)
ldif("objectClass: organizationalUnit")
ldif("ou: groups",emptyLine=True)

def getUsers():
    usernames=[]
    for group in sections:
        users=config[group]['users'].strip().split('\n')
        for user in users:
            if user not in usernames:
                usernames.append(user)
    return usernames

def getUid(username):
    name=username.split(" ")
    firstName=name[0].lower()
    lastName=name[1].lower()
    uid = firstName[0]+lastName
    return uid

def getUids(groupName):
    uids=[]
    users=config[group]['users'].strip().split('\n')
    for user in users:
        uid = getUid(user)
        if uid not in uids:
            uids.append(uid)
    return uids

#create groups
gidNumber=2001
for group in sections:
    ldif("#group: %s" % group)
    ldif("dn: cn=%s,ou=groups,%s" % (group,dcName))
    ldif("objectclass: posixGroup")
    ldif("cn: %s" % group)
    ldif("gidNumber: %d" % gidNumber)
    gidNumber = gidNumber +1
    for member in getUids(group):
        ldif("memberUid: uid=%s,ou=users,%s" % (member,dcName))
        #ldif("memberUid: %s" % (member))
    ldif("")

#create users
uidNumber=1001
for username in getUsers():
    userPassword = defaultPassword
    if username.find(":") > -1:
        usernameAndPassword = username.split(":")
        username = usernameAndPassword[0]
        userPassword = usernameAndPassword[1]
    uid = getUid(username)
    ldif("#user: %s" % username)
    ldif("dn: uid=%s,ou=users,%s" % (uid,dcName))
    ldif("objectClass: inetOrgPerson")
    ldif("objectclass: posixAccount")
    ldif("cn: %s" % username)
    ldif("givenName: %s" % username.split()[0])
    ldif("sn: %s" % username.split()[1])
    ldif("mail: %s@%s" % (uid,domain))
    ldif("userpassword: %s" % userPassword)
    ldif("uid: %s" % uid)
    ldif("gidNumber: 0")
    ldif("uidNumber: %d" % uidNumber)
    uidNumber = uidNumber +1
    ldif("homeDirectory: /home/%s" % uid,emptyLine=True)


ldifFile.close()

#create Dockerfile
dockerFile=open("Dockerfile.generated","w")
print("FROM %s" % config['globalsettings']['dockerImageBase'],file=dockerFile)
print("ENV LDAP_ORGANISATION \"%s\"" % config['globalsettings']['organization'],file=dockerFile)
print("ENV LDAP_DOMAIN \"%s\"" % domain,file=dockerFile)
print("ENV LDAP_ADMIN_PASSWORD \"%s\"" % config['globalsettings']['adminPassword'],file=dockerFile)
print("COPY %s /container/service/slapd/assets/config/bootstrap/ldif/custom/" % ldifFileName,file=dockerFile)

dockerFile.close()

print("LDIF and Docker file created")
print()
print("Build new image using:")
print("docker build -t myopenldap -f Dockerfile.generated .")
