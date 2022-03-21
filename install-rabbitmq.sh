#!/bin/bash
#README
#Copy this script to master rabbitmq node, sure was setup ssh key between from master to two slave nodes.
#Excute this script by run command "/path_to_script/install-rabbitmq.sh [IP of slave1] [IP of slave2]". Example: /opt/rabbitmq/install-rabbitmq.sh 10.10.10.10 10.10.10.11
####
#Input address of slave
deviceNIC=$(ip ad | grep ens | awk 'NR==1{print $2}' | cut -d : -f 1);
masterIP=$(ip addr show $deviceNIC | grep "inet " | awk '{print $2}' | cut -d / -f 1);
slave1="$1"
slave2="$2"

host() {
cat <<EOF | sudo tee -a /etc/hosts
$1 rabbitmq1
$2 rabbitmq2
$3 rabbitmq3
EOF
}

erlang() {
mkdir -p /opt/rabbitmq
cd /opt/rabbitmq
touch /opt/rabbitmq/.erlang.cookie
chown -R rabbitmq:rabbitmq /opt/rabbitmq/.erlang.cookie
chmod 400 /opt/rabbitmq/.erlang.cookie
cat <<EOF | sudo tee /opt/rabbitmq/.erlang.cookie
TYEVTCBYETLAMACVTTT
EOF
}
#Config file
createconfig() {
cat <<EOF | sudo tee /opt/rabbitmq/rabbitmq.conf
cluster_partition_handling = pause_minority
EOF

cat <<EOF | sudo tee /opt/rabbitmq/enabled_plugins
[rabbitmq_management,rabbitmq_prometheus,rabbitmq_shovel,rabbitmq_shovel_management].
EOF
}

#Docker-compose
composemaster() {
cat  <<EOF | sudo tee /opt/rabbitmq/docker-compose.yml
version: '3'

services:
  rabbitmq1:
    image: rabbitmq:3-management
    hostname: rabbitmq1
    container_name: rabbitmq1
    environment:
      - RABBITMQ_DEFAULT_USER=admin
      - RABBITMQ_DEFAULT_PASS=ycJHyvKGBNrgn9qY
      - RABBITMQ_DEFAULT_VHOST=/
    volumes:
      - ./storage/rabbitmq:/var/lib/rabbitmq
      - ./.erlang.cookie:/var/lib/rabbitmq/.erlang.cookie
      - ./enabled_plugins:/etc/rabbitmq/enabled_plugins
      - ./rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
    network_mode: "host"
EOF

cd /opt/rabbitmq
docker-compose up -d
}

composeslave() {
cat  <<EOF | sudo tee /opt/rabbitmq/docker-compose.yml
version: '3'

services:
  $1:
    image: rabbitmq:3-management
    hostname: $1
    container_name: $1
    volumes:
      - ./storage/rabbitmq:/var/lib/rabbitmq
      - ./.erlang.cookie:/var/lib/rabbitmq/.erlang.cookie
      - ./enabled_plugins:/etc/rabbitmq/enabled_plugins
      - ./rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
    network_mode: "host"
EOF

cd /opt/rabbitmq
docker-compose up -d
}

#Join cluster
joincluster() {
docker exec $1 rabbitmqctl stop_app
sleep 30
docker exec $1 rabbitmqctl join_cluster rabbit@rabbitmq1
sleep 30
docker exec $1 rabbitmqctl start_app
}

##Master
#Invoke funci
host $masterIP $slave1 $slave2
erlang
createconfig
composemaster
#Excute mode
sleep 60
docker exec rabbitmq1 rabbitmqctl set_policy -p "/" --priority 1 --apply-to "all" ha ".*" '{ "ha-mode": "all", "ha-sync-mode": "automatic"}'

##Install rabbit on slave
user=root
host=($slave1 $slave2)
#Slave1
typeset -f host | ssh $user@${host[0]} "$(cat); host $masterIP $slave1 $slave2"
typeset -f erlang | ssh $user@${host[0]} "$(cat); erlang"
typeset -f createconfig | ssh $user@${host[0]} "$(cat); createconfig"
typeset -f composeslave | ssh $user@${host[0]} "$(cat); composeslave rabbitmq2"
sleep 60
typeset -f joincluster | ssh $user@${host[0]} "$(cat); joincluster rabbitmq2"

#Slave2
typeset -f host | ssh $user@${host[1]} "$(cat); host $masterIP $slave1 $slave2"
typeset -f erlang | ssh $user@${host[1]} "$(cat); erlang"
typeset -f createconfig | ssh $user@${host[1]} "$(cat); createconfig"
typeset -f composeslave | ssh $user@${host[1]} "$(cat); composeslave rabbitmq3"
sleep 60
typeset -f joincluster | ssh $user@${host[1]} "$(cat); joincluster rabbitmq3"
