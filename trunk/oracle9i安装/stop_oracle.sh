#!/bin/bash
#this script is used to stop the oracle

/opt/oracle/920/bin/lsnrctl stop

su - oracle -c "/opt/oracle/920/bin/dbshut" 

chmod a+x /etc/init.d/stop_oracle.sh 
