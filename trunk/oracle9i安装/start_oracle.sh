#!/bin/bash
#this script is used to start the oracle
su - oracle -c "/opt/oracle/920/bin/dbstart"

su - oracle -c "/opt/oracle/920/bin/lsnrctl start"


 chmod a+x /etc/init.d/start_oracle.sh
