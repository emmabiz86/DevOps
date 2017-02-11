#!/bin/bash

source .env
source $ENV_INIT_SCRIPT_PATH/env_init.sh

echo "checking if ssh key pair exists or not..."

if  [ -r $AWS_SSH_KEYPATH ] && [ -r $AWS_SSH_KEYPATH.pub ]; then
	echo "ssh key pair exists, will use environment variable for AWS_SSH_KEYPATH, moving forward"
else
	echo "ssh key pair does not exist, hence will unset AWS_SSH_KEYPATH"
	echo "now ssh key pair will be generated by docker-machine itself"
	unset AWS_SSH_KEYPATH
	echo "AWS_SSH_KEYPATH unset, checking the value if still exists or not value=$AWS_SSH_KEYPATH"
fi


export AWS_ZONE_MANAGER=('a' 'b' 'a' 'b' 'a' 'b' 'a' 'b')
export AWS_ZONE_WORKER=('a' 'b' 'a' 'b' 'a' 'b' 'a' 'b' 'a' 'b' 'a' 'b' 'a' 'b' 'a' 'b' 'a')
export AWS_INSTANCE_TYPES_MANAGER=('t2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro')
export AWS_INSTANCE_TYPES_WORKER=('t2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro' 't2.micro')
export AWS_ROOT_SIZES_MANAGER=(8 8 8 8 8 8 8 8)
export AWS_ROOT_SIZES_WORKER=(8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8)


# export CLUSTER_SIZE=5
# export MANAGER_COUNT=3
# export WORKER_COUNT=5
# export MACHINE_DRIVER=amazonec2
# export AWS_ACCESS_KEY_ID=<access_key_id>
# export AWS_SECRET_ACCESS_KEY=<secret_access_key>
# export AWS_DEFAULT_REGION=ap-south-1
# export AWS_AMI=ami-dd3442b2
# export AWS_VPC_ID=<aws_vpc_id>
# export AWS_SECURITY_GROUP=docker-machine
# export AWS_VOLUME_TYPE=gp2
# export AWS_SSH_USER=ubuntu
# export AWS_SSH_KEYPATH=<path/to/custom/ssh/private/key>
# export CREATE_SWARM=yes

# --amazonec2-subnet-id	AWS_SUBNET_ID	-
# --amazonec2-device-name	AWS_DEVICE_NAME	/dev/sda1
# --amazonec2-iam-instance-profile	AWS_INSTANCE_PROFILE	-
# --amazonec2-request-spot-instance	-	false
# --amazonec2-spot-price	-	0.50
# --amazonec2-use-private-address	-	false
# --amazonec2-private-address-only	-	false
# --amazonec2-monitoring	-	false
# --amazonec2-use-ebs-optimized-instance	-	false
# --amazonec2-retries	-	5


export MAIN_SWARM_MANAGER=${CLUSTER_MANAGER_NAMES[0]}-01
echo "MAIN_SWARM_MANAGER : $MAIN_SWARM_MANAGER"
export MAIN_SWARM_MANAGER_NEW="no"

export REMOVE="docker-machine rm --force -y "
export START="docker-machine start "
export STOP="docker-machine stop "
# export IP="docker-machine ip "


function create_node() {
   
	# check if creating main master node too,
	# if yes, then mark it as newly creted/started
	# so that we will leave the earlier swarm forcefullly and 
	# update all nodes swarm configuration,
	# if not, then we will not do a forcefull swarm leave and rejoin
	if [ "$MAIN_SWARM_MANAGER" == "$5" ]; then
		MAIN_SWARM_MANAGER_NEW="yes"
	fi

	local CREATE="docker-machine create \
   		--amazonec2-zone $1 \
   		--amazonec2-tags $2 \
   		--amazonec2-instance-type $3 \
   		--amazonec2-root-size $4 \
   		$5"
   
   	# echo "CREATE : $CREATE"
   	# echo "creating node..."
   	$CREATE > /dev/null 2>&1
   	# echo "creaded now"
   	# # sleep 2
   
   	# while [ $? -ne 0 ]; do
   	#      $REMOVE $5 > /dev/null 2>&1
   	#      # sleep 2
   	#      $CREATE 2> /dev/null
   	#      # sleep 2
   	# done
}



function start_node() {
	# check if starting main master node too,
	# if yes, then mark it as newly started/created
	# so that we will leave the earlier swarm forcefullly and 
	# update all nodes swarm configuration,
	# if not, then we will not do a forcefull swarm leave and rejoin
	if [ "$MAIN_SWARM_MANAGER" == "$1" ]; then
		MAIN_SWARM_MANAGER_NEW="yes"
	fi

	$START $1  > /dev/null 2>&1
	# # sleep 2
	# while [ $? -ne 0 ]; do
	# 	$STOP $1 > /dev/null 2>&1 
	# 	# sleep 2
	# 	$START $1 2> /dev/null &
	# 	# sleep 2
	# done
}




function regenerate_certificates_docker() {
	docker-machine regenerate-certs --force $1 > /dev/null 2>&1 
}



function aws_ec2_authorize_security_group_ingress_swarm() {
  
  aws ec2 authorize-security-group-ingress \
  --group-name "$AWS_SECURITY_GROUP" \
  --source-group "$AWS_SECURITY_GROUP" \
  --protocol $1 \
  --port $2  > /dev/null 2>&1 

}


function aws_ec2_authorize_security_group_ingress_internet() {
  
  aws ec2 authorize-security-group-ingress \
  --group-name "$AWS_SECURITY_GROUP" \
  --protocol $1 \
  --port $2 \
  --cidr $3 > /dev/null 2>&1 

}



function change_docker_env_to() {

	eval $(docker-machine env $1) > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Error in changing docker environment, regenerating certs..."
		docker-machine regenerate-certs --force $1
		eval $(docker-machine env $1) > /dev/null 2>&1
	fi
}



function inspect_docker_node() {

	docker-machine ssh $1 docker node inspect $2 > /dev/null 2>&1
}




manager_index=0
worker_index=0

# create a docker swarm cluster of 3 nodes - 1 master and  2 worker
for i in $(seq 0 $((CLUSTER_SIZE-1)));
do
	NODE_TYPE="Worker"
	
	if [ $i -lt $MANAGER_COUNT ];
	then
		NODE_TYPE="Manager"
		CLUSTER_NODE_NAME=${CLUSTER_MANAGER_NAMES[$manager_index]}-0$((i+1))
		AWS_ZONE=${AWS_ZONE_MANAGER[$manager_index]}
		AWS_TAGS="Name,${CLUSTER_MANAGER_NAMES[$manager_index]}-0$((i+1))"
		AWS_INSTANCE_TYPE=${AWS_INSTANCE_TYPES_MANAGER[$manager_index]}
		AWS_ROOT_SIZE=${AWS_ROOT_SIZES_MANAGER[$manager_index]}
		manager_index=$((manager_index + 1))
	else
		NODE_TYPE="Worker"
		CLUSTER_NODE_NAME=${CLUSTER_WORKER_NAMES[$worker_index]}-0$((i+1))
		AWS_ZONE=${AWS_ZONE_WORKER[$worker_index]}
		AWS_TAGS="Name,${CLUSTER_WORKER_NAMES[$worker_index]}-0$((i+1))"
		AWS_INSTANCE_TYPE=${AWS_INSTANCE_TYPES_WORKER[$worker_index]}
		AWS_ROOT_SIZE=${AWS_ROOT_SIZES_WORKER[$worker_index]}
		worker_index=$((worker_index + 1))
	fi

	# create the the swarm nodes
	echo "[$CLUSTER_NODE_NAME] - Checking if Swarm ${NODE_TYPE} Node exists or not..."
	docker-machine ls -q | grep -w "$CLUSTER_NODE_NAME" > /dev/null 2>&1
	if [ $? -ne 0 ];
	then
		# create the swarm node
		echo "[$CLUSTER_NODE_NAME] - creating Swarm ${NODE_TYPE} Node..."
		(
			create_node  "$AWS_ZONE"  "$AWS_TAGS"  "$AWS_INSTANCE_TYPE"  "$AWS_ROOT_SIZE"  "$CLUSTER_NODE_NAME"
			echo "[$CLUSTER_NODE_NAME] - Swarm ${NODE_TYPE} Node created"
		) &

	else
		echo "[$CLUSTER_NODE_NAME] - Swarm ${NODE_TYPE} Node already exists"
		echo "[$CLUSTER_NODE_NAME] - checking ${NODE_TYPE} Node status, start if currently stopped, otherwise move forward"
		(
			docker-machine status "$CLUSTER_NODE_NAME" | grep -w "Stopped" > /dev/null 2>&1
			if [ $? -eq 0 ];
			then
				# start the stopped cluster node machine
				echo "[$CLUSTER_NODE_NAME] machine is Stopped, hence starting..."
				start_node "$CLUSTER_NODE_NAME"
				echo "[$CLUSTER_NODE_NAME] machine started Successfully"
			else
				echo "[$CLUSTER_NODE_NAME] machine is already running, moving forward"
			fi
		) &
	fi



done

echo "Wating for cluster node creation..."
wait
echo "Cluster Nodes Created"

# list the cluster machines
echo "Current Docker Hosts:"
docker-machine ls


# update the security group for ssl traffic
echo "[$AWS_SECURITY_GROUP] Updating security group for Internet"
# aws_ec2_authorize_security_group_ingress_internet tcp 443 0.0.0.0/0
# aws_ec2_authorize_security_group_ingress_internet tcp 80 0.0.0.0/0
# aws_ec2_authorize_security_group_ingress_internet tcp 8081 0.0.0.0/0
# aws_ec2_authorize_security_group_ingress_internet tcp 8082 0.0.0.0/0
echo "Updating security group for TCP Ports"
for port in "${OPEN_PORTS_TCP_INTERNET[@]}"; do
	echo "Opening tcp port : $port.."
	(
		aws_ec2_authorize_security_group_ingress_internet tcp "$port" 0.0.0.0/0
		echo "tcp port $port opened successfully"
	) &
done
echo "Updating security group for UDP Ports"
for port in "${OPEN_PORTS_UDP_INTERNET[@]}"; do
	echo "Opening udp port : $port.."
	(
		aws_ec2_authorize_security_group_ingress_internet udp "$port" 0.0.0.0/0
		echo "udp port $port opened successfully"
	) &
done



echo "Wating for opening tcp and udp ports for internet..."
wait
echo "Security Group Udpated for Internet"



echo "Checking if swarm to be created or not..."
# proceed with swarm creation only if necesssary
if [ "$CREATE_SWARM" == "yes" ]; then

	echo "Swarm Creation Starting..."
	echo "Updating security group $AWS_SECURITY_GROUP for swarm"
	##############
	### NOTE: ###
	##############
	# The following ports must be available. On some systems, these ports are open by default.
	# 
	# TCP port 2377 for cluster management communications
	# TCP and UDP port 7946 for communication among nodes
	# TCP and UDP port 4789 for overlay network traffic
	# 
	# If you are planning on creating an overlay network with encryption (--opt encrypted), 
	# you will also need to ensure ip protocol 50 (ESP) traffic is allowed.


	################################################################################################
	# update the security group docker-machine or whatever is given 
	# to open connections for docker swam since the docker-machine as of now (January, 2017)
	# is unable to create the necessary security group rules automatically
	echo "Updating security group for TCP Ports"
	for port in "${OPEN_PORTS_TCP_SWARM[@]}"; do
		echo "opening tcp port internally port : $port.."
		(
			aws_ec2_authorize_security_group_ingress_swarm tcp "$port"
			echo "tcp port $port opened internally successfully"
		) &
	done
	echo "Updating security group for UDP Ports"
	for port in "${OPEN_PORTS_UDP_SWARM[@]}"; do
		echo "opening udp port internally port : $port.."
		(
			aws_ec2_authorize_security_group_ingress_swarm udp "$port"
			echo "udp port $port opened internally successfully"
		) &
	done
	# aws_ec2_authorize_security_group_ingress_swarm tcp 2377 
	# aws_ec2_authorize_security_group_ingress_swarm tcp 7946 
	# aws_ec2_authorize_security_group_ingress_swarm udp 7946
	# aws_ec2_authorize_security_group_ingress_swarm tcp 4789
	# aws_ec2_authorize_security_group_ingress_swarm udp 4789


	echo "Wating for opening tcp and udp ports for swarm..."
	wait
	echo "Security Group Udpated for Swarm"

	export MAIN_SWARM_MANAGER=${CLUSTER_MANAGER_NAMES[0]}-01
	echo "MAIN_SWARM_MANAGER : $MAIN_SWARM_MANAGER"
	export MAIN_SWARM_MANAGER_PRIVATE_IP=$(docker-machine inspect "$MAIN_SWARM_MANAGER" | jq .Driver.PrivateIPAddress)
	echo "Main Swarm Manager Private IP : $MAIN_SWARM_MANAGER_PRIVATE_IP"


	# change docker machine env to main swarm manager
	# change_docker_env_to "$MAIN_SWARM_MANAGER"

	# check active machine status again
	# echo "Active Machine : $(docker-machine active)"

	# init swarm (need for service command); if not created
	echo "Checking if Swarm is needs to be initialized or not"
	if [ "$MAIN_SWARM_MANAGER_NEW" == "yes" ]; then
		echo "Main Swarm Manger Node has been created/started, hence new ip, thus reinitialzing swarm"
		echo "First leaving previous swarm, if any"
		docker-machine ssh "$MAIN_SWARM_MANAGER" docker swarm leave --force > /dev/null 2>&1
		echo "Initializing new swarm..."
		docker-machine ssh "$MAIN_SWARM_MANAGER" docker swarm init --advertise-addr "$MAIN_SWARM_MANAGER_PRIVATE_IP" > /dev/null 2>&1 
		echo "Swarm Initialized"
	else 
		# initialize swarm only if it is already not initialzed
		echo "Main Swarm Manager has not been creted or restarded, hence now checking if swarm is already initialzed or not.."
		docker-machine ssh "$MAIN_SWARM_MANAGER" docker node ls | grep "Leader" > /dev/null 2>&1
		if [ $? -ne 0 ]; 
		then
			# initialize swarm mode
			echo "Swarm not initialzed, hence starting..."
			echo "Initializing Swarm..."
			docker-machine ssh "$MAIN_SWARM_MANAGER" docker swarm init --advertise-addr "$MAIN_SWARM_MANAGER_PRIVATE_IP" > /dev/null 2>&1
			echo "Swarm Initialized"
		else
			echo "Swarm already initailized, moving forward"
		fi
	fi


	# save the swarm token to use in the rest of the nodes
	export SWARM_WORKER_JOIN_TOKEN=$(docker-machine ssh "$MAIN_SWARM_MANAGER" docker swarm join-token -q worker)
	export SWARM_MANAGER_JOIN_TOKEN=$(docker-machine ssh "$MAIN_SWARM_MANAGER" docker swarm join-token -q manager)

	# initialize the managers to join the swarm
	# but, before that check if the node has already joined the swarm as manager or not
	manager_index=1
	worker_index=0

	echo "Checking if the rest of the nodes are initialized, if yes, move forward, else join the swarm"
	for i in $(seq 1 $((CLUSTER_SIZE-1)));
	do

		if [ $i -lt $MANAGER_COUNT ];
		then
			CLUSTER_NODE_NAME=${CLUSTER_MANAGER_NAMES[$manager_index]}-0$((i+1))
			SWARM_JOIN_TOKEN=$SWARM_MANAGER_JOIN_TOKEN
			manager_index=$((manager_index + 1))
		else
			CLUSTER_NODE_NAME=${CLUSTER_WORKER_NAMES[$worker_index]}-0$((i+1))
			SWARM_JOIN_TOKEN=$SWARM_WORKER_JOIN_TOKEN
			worker_index=$((worker_index + 1))
		fi

		echo "[$CLUSTER_NODE_NAME] - Inspecting..."
		(
			inspect_docker_node "$MAIN_SWARM_MANAGER"  "$CLUSTER_NODE_NAME"
			# docker-machine ssh "$MAIN_SWARM_MANAGER" docker node inspect "$CLUSTER_NODE_NAME" > /dev/null 2>&1
	    	if [ $? -ne 0 ]; 
			then
				echo "$CLUSTER_NODE_NAME node have not joined $MAIN_SWARM_MANAGER manager"
				# change_docker_env_to "$CLUSTER_NODE_NAME"
				# echo "Active Machine : $(docker-machine active)"
				echo "$CLUSTER_NODE_NAME node joining swarm mananger $MAIN_SWARM_MANAGER..."
				# first leave any previous swarm if at all
				docker-machine ssh "$CLUSTER_NODE_NAME" docker swarm leave --force > /dev/null 2>&1
				docker-machine ssh "$CLUSTER_NODE_NAME" docker swarm join --token  "$SWARM_JOIN_TOKEN"  "$MAIN_SWARM_MANAGER_PRIVATE_IP":2377 > /dev/null 2>&1
				echo "$CLUSTER_NODE_NAME joined swarm managed by $MAIN_SWARM_MANAGER"
			else
				echo "$CLUSTER_NODE_NAME node already joined $MAIN_SWARM_MANAGER manager, moving forward"
			fi
		) &

		# change_docker_env_to "$MAIN_SWARM_MANAGER"
		# echo "Active Machine : $(docker-machine active)"

	done

	echo "Wating for swarm creation..."
	wait
	echo "Swarm Nodes Initialization completed"

	echo "Current Swarm Nodes:"
	docker-machine ssh "$MAIN_SWARM_MANAGER" docker node ls

else 

	echo "Swarm Creation Not Required, moving forward"
fi



manager_index=0
worker_index=0

echo "Adding user ubuntu to docker group and Installing docker-compose in each node in the swarm..."
# install docker-compose in each node
for i in $(seq 0 $((CLUSTER_SIZE-1)));
do

	if [ $i -lt $MANAGER_COUNT ];
	then
		CLUSTER_NODE_NAME=${CLUSTER_MANAGER_NAMES[$manager_index]}-0$((i+1))
		manager_index=$((manager_index + 1))
	else
		CLUSTER_NODE_NAME=${CLUSTER_WORKER_NAMES[$worker_index]}-0$((i+1))
		worker_index=$((worker_index + 1))
	fi

	echo "[$CLUSTER_NODE_NAME] - processing for swarm node..."
	(
		docker-machine ssh "$CLUSTER_NODE_NAME" '
		if ! which docker-compose > /dev/null 2>&1; then 
			echo "installing docker-compose..."
			sudo curl -L "https://github.com/docker/compose/releases/download/1.10.0/docker-compose-$(uname -s)-$(uname -m)" \
			-o /usr/local/bin/docker-compose > /dev/null 2>&1; 
			sudo chmod +x /usr/local/bin/docker-compose; 
		else
			echo "docker-compose already installed, moving forward"
		fi
		echo "adding user ubuntu to group docker"
		sudo usermod -aG docker ubuntu > /dev/null 2>&1
		if [ $? -ne 0 ]; then 
			echo "user ubuntu unable to be added to group docker"
		else
			echo "user ubuntu added to group docker successfully"
		fi
		'
	
		echo "[$CLUSTER_NODE_NAME] - processing done"
	
	) &
	
done

echo "Wating for configuration of nodes..."
wait
echo "User ubuntu addded to group docker for all nodes"
echo "docker-compose installed successfully in all nodes"



# manager_index=0
# worker_index=0

# echo "Dns management for all the nodes im the swarm"
# # add dns nameservers pointing to google nameservers in /etc/resolv.conf due to a bug/error
# # whcih does not allow to pull images from docker registry (using docker version 1.13.0)
# for i in $(seq 0 $((CLUSTER_SIZE-1)));
# do

# 	if [ $i -lt $MANAGER_COUNT ];
# 	then
# 		CLUSTER_NODE_NAME=${CLUSTER_MANAGER_NAMES[$manager_index]}-0$((i+1))
# 		manager_index=$((manager_index + 1))
# 	else
# 		CLUSTER_NODE_NAME=${CLUSTER_WORKER_NAMES[$worker_index]}-0$((i+1))
# 		worker_index=$((worker_index + 1))
# 	fi

# 	echo "adding dns entry to /etc/resolv.conf for swarm node : $CLUSTER_NODE_NAME"
# 	docker-machine ssh "$CLUSTER_NODE_NAME" \
# 	'echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | sudo  cat - /etc/resolv.conf > /tmp/out_etc_resolv \
# 	&&  sudo mv /tmp/out_etc_resolv  /etc/resolv.conf \
# 	&& sudo rm -f /tmp/out_etc_resolv >/dev/null 2>&1 &'
	
# 	echo "dns entry added successfully for $CLUSTER_NODE_NAME"

# done



echo "Provisioning Successful"
