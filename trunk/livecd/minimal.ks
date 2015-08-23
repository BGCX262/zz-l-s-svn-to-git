cp -a /bin      /mnt/rot/
 cp -a /etc      /mnt/rot/
 cp -a /exports  /mnt/rot/
 cp -a /home     /mnt/rot/
 cp -a /lib      /mnt/rot/
 cp -a /net      /mnt/rot/
 cp -a /root     /mnt/rot/
 cp -a /sbin     /mnt/rot/
 cp -a /srv      /mnt/rot/
 cp -a /tftpboot /mnt/rot/
 cp -a /usr      /mnt/rot/
 cp -a /var      /mnt/rot/
 cp -a /opt      /mnt/rot/
 cp -a /boot      /mnt/rot/

 #mkdir /mnt/rot/boot
 mkdir /mnt/rot/media
 mkdir /mnt/rot/misc
 #mkdir /mnt/rot/opt
 mkdir /mnt/rot/mnt
 mkdir /mnt/rot/proc
 chmod -w /mnt/rot/proc/
 mkdir /mnt/rot/selinux
 mkdir /mnt/rot/sys
 mkdir /mnt/rot/tmp
 chmod 777 /mnt/rot/tmp
 chmod +t /mnt/rot/tmp
