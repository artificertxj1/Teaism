#include <stdio.h>
#include <assert.h>
#include "basics/tensor.cu"
#include "basics/session.hpp"
#include "layers/data.cu"
#include "layers/softmax.cu"
#include "layers/cross_entropy_loss.cu"
#include "layers/pooling.cu"
#include "layers/conv2d.cu"
#include "layers/relu.cu"
#include "layers/fc.cu"
#include "utils/bitmap_image.hpp"

#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "utils/helper_cuda.h"
#include "utils/utils.cu"

void test_lenet_gpu() {
  cudaError_t cudaStatus = cudaSetDevice(0);
  checkCudaErrors(cudaStatus);
  show_mem(cudaStatus);
  startTimer();

  Session* session = Session::GetNewSession();
  session->gpu = true;
  session->batch_size = 64;
  size_t batch_size = session->batch_size;


  Data<float> data_layer(batch_size, "tmp/test/img_list.txt");
  // vector<size_t*> data_tops_dims;
  size_t data_tops_dims0[4];
  size_t data_tops_dims1[4];
  data_layer.GetTopsDims({}, {data_tops_dims0, data_tops_dims1});
  std::vector<Tensor<float>*> data_tops;
  data_tops.push_back(Tensor<float>::CreateTensorGPU(data_tops_dims0));
  data_tops.push_back(Tensor<float>::CreateTensorGPU(data_tops_dims1));

  Conv2D<float> conv1(5,5,3,32,1, new GaussianKernelInitializer<float>(0.1), SAME);
  size_t conv1_top_dims[4];
  conv1.GetTopsDims({data_tops_dims0}, {conv1_top_dims});
  Tensor<float> * conv1_top = Tensor<float>::CreateTensorGPU(conv1_top_dims);
  assert(conv1_top_dims[0] == batch_size);
  assert(conv1_top_dims[1] == 28);
  assert(conv1_top_dims[2] == 28);
  assert(conv1_top_dims[3] == 32);

  Pooling<float> pool1(2, MAX, 2);
  size_t pool1_top_dims[4];
  pool1.GetTopsDims({conv1_top_dims}, {pool1_top_dims});
  Tensor<float> * pool1_top = Tensor<float>::CreateTensorGPU(pool1_top_dims);
  assert(pool1_top_dims[0] == batch_size);  
  assert(pool1_top_dims[1] == 14);  
  assert(pool1_top_dims[2] == 14);  
  assert(pool1_top_dims[3] == 32);  
  
  Relu<float> relu1;
  size_t relu1_top_dims[4];
  relu1.GetTopsDims({pool1_top_dims}, {relu1_top_dims});
  Tensor<float> * relu1_top = Tensor<float>::CreateTensorGPU(relu1_top_dims);
  assert(relu1_top_dims[0] == batch_size);
  assert(relu1_top_dims[1] == 14);
  assert(relu1_top_dims[2] == 14);
  assert(relu1_top_dims[3] == 32);

  Conv2D<float> conv2(5,5,32,64,1, new GaussianKernelInitializer<float>(0.1), SAME);
  size_t conv2_top_dims[4];
  conv2.GetTopsDims({relu1_top_dims}, {conv2_top_dims});
  printf("relu1 top dims: %d %d %d %d \n", (int)relu1_top_dims[0], (int)relu1_top_dims[1], (int)relu1_top_dims[2], (int)relu1_top_dims[3]);
  printf("conv2 top dims: %d %d %d %d \n", (int)conv2_top_dims[0], (int)conv2_top_dims[1], (int)conv2_top_dims[2], (int)conv2_top_dims[3]);
  Tensor<float> * conv2_top = Tensor<float>::CreateTensorGPU(conv2_top_dims);
  assert(conv2_top_dims[0] == batch_size);  
  assert(conv2_top_dims[1] == 14);  
  assert(conv2_top_dims[2] == 14);
  assert(conv2_top_dims[3] == 64);  

  Pooling<float> pool2(2, MAX, 2);
  size_t pool2_top_dims[4];
  pool2.GetTopsDims({conv2_top_dims}, {pool2_top_dims});
  Tensor<float> * pool2_top = Tensor<float>::CreateTensorGPU(pool2_top_dims);
  assert(pool2_top_dims[0] == batch_size);  
  assert(pool2_top_dims[1] == 7);  
  assert(pool2_top_dims[2] == 7);  
  assert(pool2_top_dims[3] == 64);  

  Relu<float> relu2;
  size_t relu2_top_dims[4];
  relu2.GetTopsDims({pool2_top_dims}, {relu2_top_dims});
  Tensor<float> * relu2_top = Tensor<float>::CreateTensorGPU(relu2_top_dims);

  FC<float> fc3(7*7*64,1024);
  size_t to_fc3_dims[4];
  to_fc3_dims[0] = relu2_top_dims[0];
  to_fc3_dims[1] = 1;
  to_fc3_dims[2] = 1;
  to_fc3_dims[3] = relu2_top_dims[1]*relu2_top_dims[2]*relu2_top_dims[3];
  
  size_t fc3_top_dims[4];

  fc3.GetTopsDims({to_fc3_dims}, {fc3_top_dims});
  printf("relu2 top dims: %d %d %d %d \n", relu2_top_dims[0], relu2_top_dims[1], relu2_top_dims[2], relu2_top_dims[3]);
  printf("fc3 top dims: %d %d %d %d \n", fc3_top_dims[0], fc3_top_dims[1], fc3_top_dims[2], fc3_top_dims[3]);
  Tensor<float> * fc3_top = Tensor<float>::CreateTensorGPU(fc3_top_dims);
  assert(fc3_top_dims[0] == batch_size);
  assert(fc3_top_dims[1] == 1);
  assert(fc3_top_dims[2] == 1);
  assert(fc3_top_dims[3] == 1024);

  Relu<float> relu3;
  size_t relu3_top_dims[4];
  relu3.GetTopsDims({fc3_top_dims}, {relu3_top_dims});
  Tensor<float> * relu3_top = Tensor<float>::CreateTensorGPU(relu3_top_dims);

  FC<float> fc4(1024, 10);
  size_t fc4_top_dims[4];
  fc4.GetTopsDims({relu3_top_dims}, {fc4_top_dims});
  Tensor<float> * fc4_top = Tensor<float>::CreateTensorGPU(fc4_top_dims);
  assert(fc4_top_dims[0] == batch_size);
  assert(fc4_top_dims[1] == 1);  
  assert(fc4_top_dims[2] == 1);  
  assert(fc4_top_dims[3] == 10);  

  Softmax<float> softmax;
  size_t sm_top_dims[4];
  softmax.GetTopsDims({fc4_top_dims}, {sm_top_dims});
  Tensor<float> * sm_top = Tensor<float>::CreateTensorGPU(sm_top_dims);

  CrossEntropyLoss<float> cel;
  size_t cel_top_dims[4];
  cel.GetTopsDims({sm_top_dims, data_tops_dims1}, {cel_top_dims});
  Tensor<float> * cel_top = Tensor<float>::CreateTensorGPU(cel_top_dims);

  printf("network finished setup: %3.1f ms \n", stopTimer());
  show_mem(cudaStatus);
  cudaStatus = cudaGetLastError();
  checkCudaErrors(cudaStatus);
  

  startTimer();
  data_layer.Forward(std::vector<Tensor<float>*> (), data_tops);
  printf("data forward: %3.1f ms \n", stopTimer()); startTimer();
  conv1.Forward({data_tops[0]}, {conv1_top});
  printf("conv1 forward: %3.1f ms \n", stopTimer()); startTimer();
  pool1.Forward({conv1_top}, {pool1_top});
  printf("pool1 forward: %3.1f ms \n", stopTimer()); startTimer();
  relu1.Forward({pool1_top}, {relu1_top});
  printf("relu1 forward: %3.1f ms \n", stopTimer()); startTimer();
  conv2.Forward({relu1_top}, {conv2_top});
  printf("conv2 forward: %3.1f ms \n", stopTimer()); startTimer();
  pool2.Forward({conv2_top}, {pool2_top});
  printf("pool2 forward: %3.1f ms \n", stopTimer()); startTimer();
  relu2.Forward({pool2_top}, {relu2_top});
  printf("relu2 forward: %3.1f ms \n", stopTimer()); startTimer();
  // flatten the tensor
  Tensor<float>::ReshapeTensorGPU(relu2_top, to_fc3_dims);
  fc3.Forward({relu2_top}, {fc3_top});
  printf("fc3 forward: %3.1f ms \n", stopTimer()); startTimer();
  relu3.Forward({fc3_top}, {relu3_top});
  printf("relu3 forward: %3.1f ms \n", stopTimer()); startTimer();

  fc4.Forward({relu3_top}, {fc4_top});
  printf("fc4 forward: %3.1f ms \n", stopTimer()); startTimer();
  softmax.Forward({fc4_top}, {sm_top});
  printf("softmax forward: %3.1f ms \n", stopTimer()); startTimer();
  cel.Forward({sm_top, data_tops[1]}, {cel_top});
  printf("cel forward: %3.1f ms \n", stopTimer());
  show_mem(cudaStatus);


  startTimer();
  data_layer.Forward(std::vector<Tensor<float>*> (), data_tops);
  conv1.Forward({data_tops[0]}, {conv1_top});
  pool1.Forward({conv1_top}, {pool1_top});
  relu1.Forward({pool1_top}, {relu1_top});
  conv2.Forward({relu1_top}, {conv2_top});
  pool2.Forward({conv2_top}, {pool2_top});
  relu2.Forward({pool2_top}, {relu2_top});
  fc3.Forward({relu2_top}, {fc3_top});
  relu3.Forward({fc3_top}, {relu3_top});
  fc4.Forward({relu3_top}, {fc4_top});
  softmax.Forward({fc4_top}, {sm_top});
  cel.Forward({sm_top, data_tops[1]}, {cel_top});
  printf("finished forward: %3.1f ms \n", stopTimer());
  show_mem(cudaStatus);

  printf("%d %d %d %d \n", fc4_top_dims[0], fc4_top_dims[1], fc4_top_dims[2], fc4_top_dims[3]);
  printf("%d %d %d %d \n", data_tops_dims1[0], data_tops_dims1[1], data_tops_dims1[2], data_tops_dims1[3]);
  printf("%d %d %d %d \n", cel_top_dims[0], cel_top_dims[1], cel_top_dims[2], cel_top_dims[3]);
  printf("%d %d %d %d \n", sm_top_dims[0], sm_top_dims[1], sm_top_dims[2], sm_top_dims[3]);
  

  cudaStatus = cudaGetLastError();
  checkCudaErrors(cudaStatus);

  show_mem(cudaStatus);
}





int main() {
  test_lenet_gpu();
}
