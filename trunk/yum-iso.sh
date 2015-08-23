#!/bin/sh

mkdir /mnt/c5-iso
mount -t iso9660 -o loop /mnt/fat/centos5/CentOS_5.7_Final.iso /mnt/c5-iso 
mv /etc/yum.conf /etc/yum.conf.old

cat  > /etc/yum.conf << "EOF"
[main]
#####x232###
cachedir=/var/cache/yum
keepcache=0
debuglevel=2
logfile=/var/log/yum.log
distroverpkg=redhat-release
tolerant=1
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
bugtracker_url=http://bugs.centos.org/set_project.php?project_id=16&ref=http://bugs.centos.org/bug_report_page.php?category=yum

# Note: yum-RHN-plugin doesn't honor this.
metadata_expire=1h

installonly_limit = 5

# PUT YOUR REPOS HERE OR IN separate files named file.repo
# in /etc/yum.repos.d

[ISO]
name=iso
baseurl=file:///mnt/c5-iso
EOF

yum clean all
yum list
# cat /etc/yum.conf.auto /etc/yum.conftmp > /etc/yum.conf
