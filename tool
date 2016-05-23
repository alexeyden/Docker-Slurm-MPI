#!/bin/bash

################################################################################

BASE_IMAGE=mpi_base
WRAP_IMAGE=mpi_task_1234

SSH_CMD="/usr/sbin/sshd -D"
SSH_PORT=2222
MPI_CMD="mpitests-osu_bcast"
update_image=0

################################################################################

message() {
 #echo -e "\033[3$1m$2\033[39m"
 echo ">>>> $2"
}

################################################################################

build_base() {
 message 2 "Building base image.."
 
 cp ~/.ssh/id_rsa.pub files/tmp_id_rsa.pub

 docker build -f DockerfileBase -t $BASE_IMAGE . 
}

build_wrap() {
 message 2 "Building wrapping image.."

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

expand-node-list() {
 groups=$(echo $1 | tr "," "\n" | tr -d "node[]") 
 excl=$2
 
 nodes=""
 for line in $groups; do
  for num in $(echo $line | tr "-" " " | xargs seq); do
   if [[ node$num != $excl ]]; then 
   	nodes="$nodes node$num"
   fi
  done
 done

 echo $nodes
}

slurm-start() {
 message 2 "Bulding images.."

 [[ $update_image == 1 ]] && build 

 message 2 "Saving $WRAP_IMAGE image to /shared/tmp/images/${WRAP_IMAGE}.tar"

 [[ $update_image == 1 ]] && docker save -o /shared/tmp/images/${WRAP_IMAGE}.tar $WRAP_IMAGE

 message 2 "Copying ssh configs .."

 rm -rf /shared/tmp/ssh/$WRAP_IMAGE
 mkdir /shared/tmp/ssh/$WRAP_IMAGE
 cp ~/.ssh/id_rsa* /shared/tmp/ssh/$WRAP_IMAGE/
 cp ~/.ssh/id_rsa.pub /shared/tmp/ssh/$WRAP_IMAGE/authorized_keys
 cp files/config /shared/tmp/ssh/$WRAP_IMAGE/config

 message 2 "Running sbatch.."
 sbatch -p debug -N 2 --ntasks-per-node=1 --exclusive  --wrap  'srun ~/image/tool slurm-entry'
}

slurm-entry() {
 if [[ $SLURM_NODEID == "0" ]]; then
  slurm-host
 else
  slurm-node
 fi
}

slurm-host() {
 node=$SLURM_TOPOLOGY_ADDR

 message 2 "Node $node (host): loading image.."
 [[ $update_image == 1 ]] && docker load -i /shared/tmp/images/${WRAP_IMAGE}.tar

 message 2 "Node $node (host): awaiting nodes.."
 nodes=$(expand-node-list $SLURM_JOB_NODELIST $node)
 message 2 "Node $node (host): node list is $nodes $node (host)"

 for n in $nodes; do
  message 2 "Node $node (host): waiting node $n to start up.."

  until nc -zv $n $SSH_PORT > /dev/null 2>&1; do
   sleep 0.2
  done

  ssh-keyscan -p $SSH_PORT $n | sed "s/$n/[$n]:$SSH_PORT/g" >> /shared/tmp/ssh/$WRAP_IMAGE/known_hosts
  message 2 "Node $node (host): node $n is up.."
 done

 ssh-keyscan -p $SSH_PORT $n | sed "s/$n/[$node]:$SSH_PORT/g" >> /shared/tmp/ssh/$WRAP_IMAGE/known_hosts
 ssh-keyscan -p $SSH_PORT $n | sed "s/$n/[localhost]:$SSH_PORT/g" >> /shared/tmp/ssh/$WRAP_IMAGE/known_hosts

 message 2 "Node $node (host): starting host image.."
 
 MPIRUN_HOSTS=$(echo $nodes | tr " " ",")
 MPIRUN_CMD="mpirun -mca btl tcp,self -np $(( $SLURM_NPROCS * $SLURM_CPUS_ON_NODE )) --map-by ppr:$SLURM_CPUS_ON_NODE:node -H localhost,$MPIRUN_HOSTS $MPI_CMD"
 message 2 "Node $node (host): mpirun cmd is $MPIRUN_CMD"
 HOST_CMD="/usr/sbin/sshd && su $(id -un) -c '(source /etc/profile && module load mpi/openmpi-x86_64; $MPIRUN_CMD)' && pkill sshd"

 docker run \
	--net=host \
	-v /shared/home/$USER/:/home/$USER/ \
 	-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
	--rm $WRAP_IMAGE bash -c "$HOST_CMD" 
 
 message 2 "Node $node (host): terminating nodes"
 
 scancel -s USR1 $SLURM_JOBI

 rm -rf /shared/tmp/ssh/$WRAP_IMAGE

 exit 0
}

slurm-node() {
 node=$SLURM_TOPOLOGY_ADDR

 message 4 "Node $node: loading image.."
 [[ $update_image == 1 ]] && docker load -i /shared/tmp/images/${WRAP_IMAGE}.tar

 message 4 "Node $node: running container.."

 container_id=$(docker run --net=host  -v /shared/home/$USER/:/home/$USER/ \
			-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
			-d $WRAP_IMAGE $SSH_CMD)

 message 4 "Node $node: node is up"
 
 trap "slurm-node-term $container_id" SIGINT SIGTERM USR1 
 
 while true; do
  sleep 1s
 done
}

slurm-node-term() {
 node=$SLURM_TOPOLOGY_ADDR
 
 message 4 "Node $node: terminating node"
 
 docker stop $1  
 docker rm $1
 
 exit 0
}

run-mpitest() {
 docker run \
	--net=host \
	-v /shared/home/$USER/:/home/$USER/ \
	-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
	-u $(id -un) \
	$WRAP_IMAGE /usr/lib64/openmpi/bin/mpirun --prefix /usr/lib64/openmpi -H node20 -n 16 /opt/mpitest
}

debug-host() {
 ssh-keyscan -p $SSH_PORT node20 | sed "s/node20/[node20]:$SSH_PORT/g" >> /shared/tmp/ssh/$WRAP_IMAGE/known_hosts
 ssh-keyscan -p $SSH_PORT node20 | sed "s/node20/[localhost]:$SSH_PORT/g" >> /shared/tmp/ssh/$WRAP_IMAGE/known_hosts
 docker run \
	--net=host \
	-v /shared/home/$USER/:/home/$USER/ \
	-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
	-u $(id -un) -it \
	$WRAP_IMAGE /bin/bash
}

debug-node() {
 rm -rf /shared/tmp/ssh/$WRAP_IMAGE
 mkdir /shared/tmp/ssh/$WRAP_IMAGE
 cp ~/.ssh/id_rsa* /shared/tmp/ssh/$WRAP_IMAGE/
 cp ~/.ssh/id_rsa.pub /shared/tmp/ssh/$WRAP_IMAGE/authorized_keys
 cp files/config /shared/tmp/ssh/$WRAP_IMAGE/config

 docker run --net=host  -v /shared/home/$USER/:/home/$USER/ \
			-v /shared/tmp/ssh/$WRAP_IMAGE/:/home/$USER/.ssh/ \
			$WRAP_IMAGE /usr/sbin/sshd -D -dd
}

clean() {
 rm -rf slurm-*.out
}

################################################################################

if [[ -z $1 ]]; then
 slurm-start
else
 $1 $2
fi

