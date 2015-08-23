# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
        . ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/bin

ORACLE_BASE=/opt/oracle
ORACLE_HOME=$ORACLE_BASE/920
ORACLE_SID=orcl
LD_LIBRARY_PATH=$ORACLE_HOME/lib
ORACLE_OEM_JAVARUNTIME=/opt/jre1.3.1_19
PATH=$PATH:$ORACLE_HOME/bin

export ORACLE_BASE ORACLE_HOME ORACLE_SID LD_LIBRARY_PATH ORACLE_OEM_JAVARUNTIME PATH
#export NLS_LANG="American_america.zhs16gbk"
export NLS_LANG="American_america.utf8"
export DISPLAY=:0
#export LANG=en_US
export LANG=en_US
export GDM_LANG=en_US
export LC=en_US
unset USENAME
