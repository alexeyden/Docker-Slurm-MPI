#include <mpi.h>
#include <stdio.h>

int main(int argc, char** argv) {
    MPI_Init(NULL, NULL);

    int world_size;
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    int world_rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);

    char processor_name[MPI_MAX_PROCESSOR_NAME];
    int name_len;
    MPI_Get_processor_name(processor_name, &name_len);

    char buf[1024];
    FILE* fp = popen("uname -a", "r");
   
    int s = 0;
    while(!feof(fp)) {
      fread(buf + s++, 1, 1, fp);
    }
    buf[s-1] = 0;
    fclose(fp);

    char test[10] = "none";
    if(world_rank == 0) {
	memcpy(test, "OK", 3);

	for(int i = 1; i < world_size; i++) {
	  MPI_Send(&test, 10, MPI_CHAR, i, 0, MPI_COMM_WORLD);
	}
	memcpy(test, "host", 5);
    }
    else {
	MPI_Status s;
	MPI_Recv(&test, 10, MPI_CHAR, 0, 0, MPI_COMM_WORLD, &s); 
    }

    printf("Node %s\n\trank = %d of %d\n\tuname -a = %s\tmsg = %s\n", processor_name, world_rank, world_size, buf, test);

    MPI_Finalize();
}

