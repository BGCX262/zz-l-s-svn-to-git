#!/bin/sh

#安装libgcc
cd /tmp
yum install gcc
rpm -ivh compat-gcc-7.3-2.96.126.i386.rpm compat-libgcc-296-2.96-138.i386.rpm compat-libstdc++-296-2.96-138.i386.rpm compat-libstdc++-33-3.2.3-61.i386.rpm

cd /usr/lib
ln -s libstdc++-3-libc6.2-2-2.10.0.so libstdc++-libc6.1-1.so.2  

yum install libXp

#隐藏文件
cd /usr/bin
mv ./gcc ./gcc3
mv ./gcc296 ./gcc

#安装JDK
cd /tmp
chmod +x j2re-1_3_1_19-linux-i586.bin
./j2re-1_3_1_19-linux-i586.bin
mv jre1.3.1_19 /opt/ 

#cd /tmp
#rpm -Uvh --force --nodeps binutils-2.10.91.0.2-3.i386.rpm

#创建oracle用户和组
#groupadd oinstall
groupadd dba
useradd -g dba oracle
#useradd oracle -g oinstall -G dba
passwd oracle
cd /opt/data
mkdir oracle
# chown oracle:dba oracle 
chown -R oracle.dba /opt/data/oracle
chmod 750 /opt/data/oracle

cp /tmp/c57-o9i.bash_profile /home/oracle/.bash_profile
cp /etc/sysconfig/i18n /home/oracle/.i18n
cd /tmp
gunzip ship_9204_linux_disk1.cpio.gz
gunzip ship_9204_linux_disk2.cpio.gz
gunzip ship_9204_linux_disk3.cpio.gz

cpio -idmv < ship_9204_linux_disk1.cpio
cpio -idmv < ship_9204_linux_disk2.cpio
cpio -idmv < ship_9204_linux_disk3.cpio 

