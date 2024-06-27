#include <iostream>
#include <stdio.h>
#include <cuda.h>

#define max_N 100000
#define max_P 30
#define BLOCKSIZE 1024
#define SLOTSIZE 24



using namespace std;

// ****************************************************************************
// Write down the kernels here


__global__ void calculating_newRequest(int facilityCount, int* d_RequestPrefix, unsigned int* d_Request, int* d_req_id, int* d_req_cen, int* d_req_fac, int *facilityPrefix, int R, int * d_newRequest){
    int tid = (blockIdx.x * blockDim.x) + threadIdx.x;
    if(tid < R){
        int a = d_req_cen[tid];
        int b = d_req_fac[tid];
        int location = facilityPrefix[a] + b;
        if(d_Request[location] > 0){
            int val = atomicSub(&d_Request[location],1);
            if(location < 1)
                d_newRequest[val - 1] = d_req_id[tid];
            else
                d_newRequest[val + d_RequestPrefix[location-1] -1] = d_req_id[tid];    
        }
    }
}

__device__ void sortDevice(int start, int end, int *vec){
    int i, j; 
    for (i = start + 1; i < end; i++) { 
        int val = vec[i]; 
        for (j=i-1; j >= start && vec[j] > val; j--){
            vec[j+1] = vec[j]; 
        }
        vec[j+1] = val; 
    } 
}

__global__ void requestSorting(int * newReq,int * prefixSumNew,unsigned int * d_request,int totalFacilities){
    int id = (blockIdx.x * blockDim.x) + threadIdx.x;
    if(id < totalFacilities){
        if(d_request[id] != 0 and id == 0)
            sortDevice(0, prefixSumNew[id], newReq);
        else if(d_request[id] != 0 and id != 0)
            sortDevice(prefixSumNew[id - 1], prefixSumNew[id], newReq);
        }
}

__device__ void requestCompute(int facilityCount, int * arr, int start_index, int end_index, int capacity, int* d_req_start, int* d_req_slot,int * d_slots,bool *d_statusChecking,int n, int *d_req_cen, unsigned int *d_succ_reqs){
    for(int i = start_index; i < end_index; i++){
        int val = 1;
        int startingSlot = d_req_start[arr[i]];
        int requiredSlot = d_req_slot[arr[i]];
        for(int j = startingSlot ; j < startingSlot + requiredSlot; j++){
            if(d_slots[n * SLOTSIZE + j] >= capacity){
                val = 0;
                break;
            }
        }
        if(val == 0){
            d_statusChecking[i] = false;
        }
        else{
            d_statusChecking[i] = true;
            atomicInc(&d_succ_reqs[d_req_cen[arr[i]]], max_N * max_P);
            for(int j = startingSlot ; j < startingSlot + requiredSlot; j++){      
                d_slots[n * SLOTSIZE + j]++;
            }
        }  
    }
}

__global__ void calculating_requestCompute(int facilityCount, int * newReq, int * prefixSumNew, unsigned int * d_request, int totalFacilities, int *capacity, int *d_req_start, int *d_req_slot, bool *d_statusChecking, int * d_slots, int *d_req_cen, unsigned int *d_succ_reqs){
    int tid = (blockIdx.x * blockDim.x) + threadIdx.x;
    if(tid < totalFacilities){
        if(d_request[tid] != 0){
            if(tid == 0){
                requestCompute(facilityCount, newReq,0,prefixSumNew[tid], capacity[tid], d_req_start, d_req_slot, d_slots, d_statusChecking,0, d_req_cen, d_succ_reqs);
            }
            else{
                requestCompute(facilityCount, newReq, prefixSumNew[tid - 1],prefixSumNew[tid], capacity[tid], d_req_start, d_req_slot, d_slots, d_statusChecking,tid, d_req_cen, d_succ_reqs);
            }
        }
    }
}

__global__ void calculating_Request(int* req_id, int* req_cen, int* req_fac, unsigned int *d_request, int R, int *facilityPrefix){
    int id = (blockIdx.x * blockDim.x) + threadIdx.x;
    if(id < R){
        atomicInc(&d_request[facilityPrefix[req_cen[id]] + req_fac[id]], max_N * max_P);
    }
}

__global__ void countGrants(bool *statusChecking, int R, int *d_count){
    int id = threadIdx.x + blockIdx.x * blockDim.x;
    if(id < R && statusChecking[id]){
        atomicAdd(&d_count[0], 1);
    }
}



//*********************************************************************

int main(int argc,char **argv)
{
	// variable declarations...
    int N,*centre,*facility,*capacity,*fac_ids, *succ_reqs, *tot_reqs;
    

    FILE *inputfilepointer;
    
    //File Opening for read
    char *inputfilename = argv[1];
    inputfilepointer    = fopen( inputfilename , "r");

    if ( inputfilepointer == NULL )  {
        printf( "input.txt file failed to open." );
        return 0; 
    }

    fscanf( inputfilepointer, "%d", &N ); // N is number of centres
	
    // Allocate memory on cpu
    centre=(int*)malloc(N * sizeof (int));  // Computer  centre numbers
    facility=(int*)malloc(N * sizeof (int));  // Number of facilities in each computer centre
    fac_ids=(int*)malloc(max_P * N  * sizeof (int));  // Facility room numbers of each computer centre
    capacity=(int*)malloc(max_P * N * sizeof (int));  // stores capacities of each facility for every computer centre 


    int success=0;  // total successful requests
    int fail = 0;   // total failed requests
    tot_reqs = (int *)malloc(N*sizeof(int));   // total requests for each centre
    succ_reqs = (int *)malloc(N*sizeof(int)); // total successful requests for each centre

    // Input the computer centres data
    int k1=0 , k2 = 0;
    for(int i=0;i<N;i++)
    {
      fscanf( inputfilepointer, "%d", &centre[i] );
      fscanf( inputfilepointer, "%d", &facility[i] );
      
      for(int j=0;j<facility[i];j++)
      {
        fscanf( inputfilepointer, "%d", &fac_ids[k1] );
        k1++;
      }
      for(int j=0;j<facility[i];j++)
      {
        fscanf( inputfilepointer, "%d", &capacity[k2]);
        k2++;     
      }
    }

    // variable declarations
    int *req_id, *req_cen, *req_fac, *req_start, *req_slots;   // Number of slots requested for every request
    
    // Allocate memory on CPU 
	int R;
	fscanf( inputfilepointer, "%d", &R); // Total requests
    req_id = (int *) malloc ( (R) * sizeof (int) );  // Request ids
    req_cen = (int *) malloc ( (R) * sizeof (int) );  // Requested computer centre
    req_fac = (int *) malloc ( (R) * sizeof (int) );  // Requested facility
    req_start = (int *) malloc ( (R) * sizeof (int) );  // Start slot of every request
    req_slots = (int *) malloc ( (R) * sizeof (int) );   // Number of slots requested for every request
    
    // Input the user request data
    for(int j = 0; j < R; j++)
    {
       fscanf( inputfilepointer, "%d", &req_id[j]);
       fscanf( inputfilepointer, "%d", &req_cen[j]);
       fscanf( inputfilepointer, "%d", &req_fac[j]);
       fscanf( inputfilepointer, "%d", &req_start[j]);
       fscanf( inputfilepointer, "%d", &req_slots[j]);
       tot_reqs[req_cen[j]]+=1;  
    }
		

    // ***********************************************************************
    // Calling the kernels here

    int *facilityPrefix, *d_facilityPrefix;
    facilityPrefix = (int*) malloc(N * sizeof(int));
    cudaMalloc(&d_facilityPrefix, N * sizeof(int));  

    int facilityCount;
    facilityPrefix[0] = 0;

    // PREFIX SUM calculation
    for(int i = 1; i < N; i++){ 
        int prevFacilityPrefix = facilityPrefix[i-1];
        int prevFacility = facility[i-1];
        facilityPrefix[i] = prevFacilityPrefix + prevFacility;
    }

    facilityCount = facilityPrefix[N-1] + facility[N-1];

    int *d_req_id, *d_req_cen, *d_req_fac, *d_req_start, *d_req_slots;
    unsigned int *d_succ_reqs; 

    cudaMemcpy(d_facilityPrefix, facilityPrefix, N * sizeof(int), cudaMemcpyHostToDevice);

    cudaMalloc(&d_succ_reqs, N * sizeof(unsigned int)); // Device successful requests
    cudaMemcpy(d_succ_reqs, succ_reqs, N * sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaMemset(d_succ_reqs, 0,  N * sizeof(unsigned int));

    cudaMalloc(&d_req_id, R * sizeof(int));  // Device Request ids 
    cudaMemcpy(d_req_id, req_id, R * sizeof(int), cudaMemcpyHostToDevice);

    cudaMalloc(&d_req_cen, R * sizeof(int));  // Device Requested computer centre
    cudaMemcpy(d_req_cen, req_cen, R * sizeof(int), cudaMemcpyHostToDevice);

    cudaMalloc(&d_req_fac, R * sizeof(int));  // Device Requested facility
    cudaMemcpy(d_req_fac, req_fac, R * sizeof(int), cudaMemcpyHostToDevice);

    cudaMalloc(&d_req_start, R * sizeof(int));  // Device Start slot of every request
    cudaMemcpy(d_req_start, req_start, R * sizeof(int), cudaMemcpyHostToDevice);

    cudaMalloc(&d_req_slots, R * sizeof(int));   // Device Number of slots requested for every request
    unsigned int *d_Request;
    cudaMemcpy(d_req_slots, req_slots, R * sizeof(int), cudaMemcpyHostToDevice);

    int *Request, *d_capacity;

    Request = (int*)malloc(facilityCount * sizeof (int));
    cudaMalloc(&d_capacity, max_P * N * sizeof (int));
    cudaMalloc(&d_Request, facilityCount * sizeof(unsigned int)); 

    cudaMemcpy(d_capacity, capacity, max_P * N * sizeof(int), cudaMemcpyHostToDevice);

    dim3 Grid1(ceil((float)R / BLOCKSIZE), 1, 1); 
    dim3 Block1(BLOCKSIZE, 1, 1);

    cudaMemset(d_Request, 0, facilityCount * sizeof(unsigned int));

    calculating_Request<<<Grid1, Block1>>> (d_req_id, d_req_cen, d_req_fac, d_Request, R, d_facilityPrefix);
    cudaDeviceSynchronize();

    cudaMemcpy(Request, d_Request, facilityCount * sizeof(int), cudaMemcpyDeviceToHost);


    int *RequestPrefix;
    RequestPrefix = (int *) malloc ( facilityCount * sizeof (int) );
    
    int sum = 0;

    // PREFIX SUM calculation
    for(int i = 0; i < facilityCount; i++){
        sum+= Request[i];
        RequestPrefix[i] = sum;
    }
    
    int *d_RequestPrefix;
    cudaMalloc(&d_RequestPrefix, facilityCount * sizeof(int)); 

    cudaMemcpy(d_RequestPrefix, RequestPrefix, facilityCount * sizeof(int), cudaMemcpyHostToDevice);
    cudaDeviceSynchronize();
    
    int *d_newRequest;
    cudaMalloc(&d_newRequest, R * sizeof(int)); 

    calculating_newRequest<<<Grid1, Block1>>> (facilityCount, d_RequestPrefix, d_Request, d_req_id, d_req_cen, d_req_fac, d_facilityPrefix, R, d_newRequest);
    cudaDeviceSynchronize();

    cudaMemcpy(d_Request, Request, facilityCount * sizeof(int), cudaMemcpyHostToDevice);

    int *h_newRequest = (int *) malloc ( (R) * sizeof (int) ); 
    cudaMemcpy(h_newRequest, d_newRequest, R * sizeof(int), cudaMemcpyDeviceToHost);


    dim3 Grid2(ceil((float)facilityCount / BLOCKSIZE), 1, 1); 
    dim3 Block2(BLOCKSIZE, 1, 1);

    int *d_slots;
    cudaMalloc(&d_slots, SLOTSIZE * facilityCount * sizeof(int));
    cudaMemset(d_slots, 0, SLOTSIZE * facilityCount * sizeof(int));

    requestSorting<<<Grid2, Block2>>>(d_newRequest, d_RequestPrefix, d_Request, facilityCount);
    cudaDeviceSynchronize();

    bool *statusChecking, *d_statusChecking;

    statusChecking = (bool *)malloc(R * sizeof(bool));

    cudaMalloc(&d_statusChecking, R * sizeof(bool));

    calculating_requestCompute<<<Grid2, Block2>>>(facilityCount, d_newRequest, d_RequestPrefix, d_Request, facilityCount, d_capacity, d_req_start, d_req_slots, d_statusChecking, d_slots, d_req_cen, d_succ_reqs);

    cudaDeviceSynchronize();
    cudaMemcpy(succ_reqs, d_succ_reqs, N * sizeof(unsigned int), cudaMemcpyDeviceToHost);

    cudaMemcpy(statusChecking, d_statusChecking, R * sizeof(bool), cudaMemcpyDeviceToHost);

    int *count, *d_count;
    count = (int *) malloc (1 * sizeof (int)); 
    cudaMalloc(&d_count, 1 * sizeof(int)); 
    cudaMemset(d_count, 0, 1 * sizeof(int));

    countGrants<<<Grid1, Block1>>>(d_statusChecking, R, d_count);
    cudaDeviceSynchronize();
    cudaMemcpy(count, d_count, 1 * sizeof(int), cudaMemcpyDeviceToHost);

    success = count[0];
    fail = R - success;

    // ****************************************************************************
    // Output

    char *outputfilename = argv[2]; 
    FILE *outputfilepointer;
    outputfilepointer = fopen(outputfilename,"w");

    fprintf( outputfilepointer, "%d %d\n", success, fail);

    for(int j = 0; j < N; j++){
        fprintf( outputfilepointer, "%d %d\n", succ_reqs[j], tot_reqs[j]-succ_reqs[j]);
    }

    fclose( inputfilepointer );
    fclose( outputfilepointer );

    cudaDeviceSynchronize();
	return 0;
}