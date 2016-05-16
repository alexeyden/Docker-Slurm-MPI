#!/bin/bash

################################################################################

BASE_IMAGE=mpi_base
WRAP_IMAGE=mpi_task_1234

SSH_CMD="/usr/sbin/sshd -D"
SSH_PORT=2222

NODES="node20"

################################################################################

message() {
 echo -e "\033[3$1m$2\033[39m"
}

################################################################################

build_base() {
 message 3 "Building base image.."
 
 cp ~/.ssh/id_rsa.pub files/tmp_id_rsa.pub

 docker build -f DockerfileBase -t $BASE_IMAGE . 
}

build_wrap() {
 message 3 "Building wrapping image.."

 tmp_file=$(mktemp DockerfileWrap.XXXXXXXX)
 bash DockerfileWrap.skel > $tmp_file

 docker build -f $tmp_file -t $WRAP_IMAGE .
 
 rm $tmp_file
}

build() {
 [[ $1 ]] && build_$1
 [[ -z $1 ]] && build_base && build_wrap
}

################################################################################

run() {
 message 2 "Bulding images.."

 build 

 message 2 "Saving $WRAP_IMAGE image to /shared/tmp/images/${WRAP_IMAGE}.tar"

 docker save -o /shared/tmp/images/${WRAP_IMAGE}.tar $WRAP_IMAGE

 message 2 "Copying ssh configs .."

 rm -rf /shared/tmp/ssh/$WRAP_IMAGE
 mkdir /shared/tmp/ssh/$WRAP_IMAGE
 cp ~/.ssh/id_rsa* /shared/tmp/ssh/$WRAP_IMAGE/
 cp ~/.ssh/id_rsa.pub /shared/tmp/ssh/$WRAP_IMAGE/authorized_keys
 cp files/config /shared/tmp/ssh/$WRAP_IMAGE/config

 message 2 "Setting up nodes.."

 for node in $NODES; do
  message 2 "Loading image on node $node .."

  ssh $node "docker load -i /shared/tmp/images/${WRAP_IMAGE}.tar; \
             docker run --net=host -v /shared/home/$USER/:/home/$USER/ \
				   -v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
				   -d $WRAP_IMAGE $SSH_CMD"

  message 2 "Waiting node $node to start up.."
  until nc -zv $node $SSH_PORT; do
   sleep 0.2
  done

  ssh-keyscan -p $SSH_PORT $node | sed "s/$node/[$node]:$SSH_PORT/g" >> /shared/tmp/ssh/$WRAP_IMAGE/known_hosts

  message 2 "$node is running.."
 done

 message 2 "Starting host image.."

 exit 0 
 docker run \
	--net=host \
	-v /shared/home/$USER/:/home/$USER/ \
 	-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
 	-u $(id -un) \
	$WRAP_IMAGE $1 
}

run-mpitest() {
 docker run \
	--net=host \
	-v /shared/home/$USER/:/home/$USER/ \
	-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
	-u $(id -un) \
	$WRAP_IMAGE /usr/lib64/openmpi/bin/mpirun --prefix /usr/lib64/openmpi -H n20 -n 16 /opt/mpitest
}

run-shell() {
 docker run \
	--net=host \
	-v /shared/home/$USER/:/home/$USER/ \
	-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
	-u $(id -un) -it \
	$WRAP_IMAGE /bin/bash
}

################################################################################

$1 $2
