#create LDIF file from directory.ini

import sys
import configparser

config = configparser.ConfigParser(strict=False)
config.read('directory.ini')

#read global settings
domain = config['globalsettings']['domain']
defaultPassword = config['globalsettings']['defaultPassword']

dcName=[]
for domainPart in domain.split("."):
    dcName.append("dc="+domainPart)
dcName=",".join(dcName)

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
#  dn: dc=farawaygalaxy,dc=net
#  objectClass: dcObject
#  objectClass: organization
#  dc: farawaygalaxy
#  o : farawaygalaxy

# users, as organizational unit
dn: ou=users,dc=farawaygalaxy,dc=net
objectClass: organizationalUnit
ou: users

# groups, as organizational unit
dn: ou=groups,dc=farawaygalaxy,dc=net
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
    return uid

def getDN(uid):
    return "uid=%s,ou=users,%s" % (uid,dcName)

#add users to LDIF
for group in groupSections:
    cfg=config[group]
    for user in config.options(group):
        pwd=cfg[user]
        if pwd == "":
            pwd = defaultPassword
        name=user.split()
        cn=user.title()
        uid=getUID(user)
        sn=""
        if len(name) == 1:
            sn=name[0].title()
        else:
            sn=name[1].title()
        print(name[0])
        print(user)
        print("pwd: " + pwd)
        ldif("#user: " + cn)
        ldif("dn: %s" % (getDN(uid)))
        ldif("objectClass: inetOrgPerson")
        ldif("cn: " + cn)
        ldif("sn: " + sn)
        ldif("uid: " + uid)
        ldif("userPassword: " + pwd,emptyLine=True)


#add groups to LDIF
for groupName in groupSections:
    print(groupName)
    ldif("dn: cn=%s,ou=groups,%s" % (groupName,dcName))
    ldif("objectClass: groupOfUniqueNames")
    ldif("cn: " + groupName)
    #users in group
    for user in config.options(groupName):
        ldif("uniqueMember: " + getDN(getUID(user)))
    ldif("")

ldifFile.close()