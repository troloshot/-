#!/bin/bash

. $HOME/.bash_profile

if [[ $# -ne 2 ]]; then
    echo "Illegal number $# of expecting parameters(2)"
    echo "Usage $0 role[leader, neighbor_replica, replica, cascade_replica] command"
    exit 2
fi

CURRENT_ROLE="any"
expect_role=$1
command=$2

psql="psql -t -A"
leader_query="select case when pg_is_in_recovery() then 0 else 1 end as leader;"


### check localhost is leader ###
me_is_leader=$($psql -c "$leader_query")
[ $me_is_leader -eq 1 ] && CURRENT_ROLE="leader"


if [ $CURRENT_ROLE != "leader" ]; then
    ### get connection parameters for replication source ###
    query="select regexp_split_to_table(conninfo,' ') as conninfo from pg_stat_wal_receiver;"
    conninfo=$($psql -c "$query")

    if [ -z "$conninfo" ]; then
        echo "me is leader in recovery?"
        exit 1
    fi

    CURRENT_ROLE="replica"
fi

if [ $CURRENT_ROLE = "replica" ]; then
    ### check replication source server is leader (not standby leader) ###
    eval "$conninfo"
    source_user=$user
    source_passfile=$passfile
    source_host=$host
    source_is_leader=$(PGPASSFILE=$source_passfile $psql -U $source_user -h $source_host postgres -c "$leader_query")

    [ $source_is_leader -eq 0 ] && CURRENT_ROLE="cascade_replica"
fi

if [ $CURRENT_ROLE = "replica" ]; then
    ### check replication source server in L2 segment ###
    ping -W1 -c3 -r $source_host > /dev/null 2>&1
    RETVAL=$?
    [ $RETVAL -eq 0 ] && CURRENT_ROLE="neighbor_replica"
fi

if [ $CURRENT_ROLE = $expect_role ]; then
    eval "$command"
    RETVAL=$?
    logger -t "run_if_role[$$]" -plocal0.info "role: \"$CURRENT_ROLE\" command: \"$command\" status: \"$RETVAL\""
fi
