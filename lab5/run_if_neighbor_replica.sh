#!/bin/bash

. /pgsql/.bash_profile

psql="/opt/pgpro/std-10/bin/psql -t -A"
leader_query="select case when pg_is_in_recovery() then 0 else 1 end as leader;"
command=$1

### check localhost is leader and exit ###
me_is_leader=$($psql -c "$leader_query")
#echo "me_is_leader $me_is_leader"
[ $me_is_leader -eq 1 ] && exit 1

### get connection parameters for replication source ###
query="select regexp_split_to_table(conninfo,' ') as conninfo from pg_stat_wal_receiver;"
conninfo=$($psql -c "$query")
eval "$conninfo"
source_user=$user
source_passfile=$passfile
source_host=$host

### check replication source server is leader (not standby leader) ###
source_is_leader=$(PGPASSFILE=$source_passfile $psql -U $source_user -h $source_host postgres -c "$leader_query")
#echo "source_is_leader $source_is_leader"
[ $source_is_leader -eq 1 ] || exit 1

### check replication source server in L2 segment ###
ping -W1 -c3 -r $source_host > /dev/null 2>&1
RETVAL=$?
if [ $RETVAL -eq 0 ]; then
    #echo "I am the leader's neighbor in the same L2 segment"
    eval $command
else
    #echo "I am the leader's neighbor in the different L2 segment"
    exit 1
fi
