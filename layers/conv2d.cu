
#ifndef CONV2D_LAYER_CUH_
#define CONV2D_LAYER_CUH_

#include <assert.h>
#include <stdio.h>
#include "basics/layer.hpp"
#include "basics/tensor.cu"
#include "basics/session.hpp"
#include "basics/initializer.hpp"
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "utils/helper_cuda.h"
#include "utils/helper_string.h"
#include "initializers/gaussian_kernel_initializer.cu"

// TODO: implement CUDA kernel for backward()

#define BLOCKDIM 32


template <class Dtype>
__global__ void conv(Tensor<Dtype> * bottom, Tensor<Dtype> * top, Tensor<Dtype> * W, Tensor<Dtype> * b, int bi, int o, int stride) {
  // bi is the index of the tensor
  // o is the output channel
  int x_top = (blockDim.x * blockIdx.x) + threadIdx.x;
  int y_top = (blockDim.y * blockIdx.y) + threadIdx.y;
  int x = x_top*stride;
  int y = y_top*stride;
  if (!top->isValidIdx(bi, y, x, o)) {
    return;
  }

  size_t kernel_height = W->GetDims()[0];
  size_t kernel_width = W->GetDims()[1];
  W->GetDataPtr();
  int idx[4] = {bi, y, x, o};
  size_t in_channels = bottom->GetDims()[3];
  Dtype sum = 0.0;
  for(int c = 0; c < in_channels; c++) {
    for(int i = 0; i < kernel_height; i++) {
      for(int j = 0; j < kernel_width; j++) {
        // (n, hei, wid, channel),   // (hei, wid, input, output)
        sum += bottom->atPadding(idx[0], idx[1]+i-int(kernel_height/2), idx[2]+j-int(kernel_width/2), c) * W->at(i, j, c, idx[3]);
      }
    }
  }
  sum += b->at(0, 0, 0, 0);
  top->at(bi, y_top, x_top, o) = sum;
}

template <class Dtype>
__global__ void ForwardGPU(Tensor<Dtype> * bottom, Tensor<Dtype> * top, Tensor<Dtype> * W_, Tensor<Dtype> * b_, int stride) {
  size_t n = bottom->GetDims()[0];
  size_t hei = top->GetDims()[1];
  size_t wid = top->GetDims()[2];
  size_t out_channels = top->GetDims()[3];

  dim3 blocksInGrid(wid / BLOCKDIM + 1, hei / BLOCKDIM + 1);
  dim3 threadsPerBlock(BLOCKDIM, BLOCKDIM);
  for (int b = 0; b < n; b++) {
    for (int o = 0; o < out_channels; o++) {
      conv<Dtype><<<blocksInGrid, threadsPerBlock>>>(bottom, top, W_, b_, b, o, stride);
    }
  }
}

template <class Dtype>
class Conv2D: public Layer<Dtype> {
public:
  // use the same initializer to initialize W_ and b_
  Conv2D(size_t kernel_height, size_t kernel_width, size_t in_channels, 
    size_t out_channels, size_t stride, Initializer<Dtype>* initializer = NULL):
      kernel_height(kernel_height), kernel_width(kernel_width),
      in_channels(in_channels), out_channels(out_channels), 
      stride(stride), initializer_(initializer) {
    size_t w_dims[4] = {kernel_height, kernel_width, in_channels, out_channels};
    size_t b_dims[4] = {1, 1, 1, out_channels};  
    if (Session::GetSession()->gpu) {
      W_ = Tensor<Dtype>::CreateTensorGPU(w_dims);
      b_ = Tensor<Dtype>::CreateTensorGPU(b_dims);
    } else {
      W_ = Tensor<Dtype>::CreateTensorCPU(w_dims);
      b_ = Tensor<Dtype>::CreateTensorCPU(b_dims);
    }
    InitParams();
  }

  ~Conv2D() {
    if (Session::GetSession()->gpu) {
      if (W_!= NULL) {
        cudaFree(W_);
        W_ = NULL;
      }
      if (b_ != NULL) {
        cudaFree(b_);
        b_ = NULL;
      }
    } else {
      if(W_ != NULL) {
        delete W_;
        W_ = NULL;
      }
      if(b_ != NULL) {
        delete b_;
        b_ = NULL;
      }
    }
  }

  void Forward(Tensor<Dtype> * bottom, Tensor<Dtype> * top) {
    if (Session::GetSession()->gpu) {
      ForwardGPU<<<1,1>>>(bottom, top, W_, b_, stride);
    } else {
      for(int b = 0; b < bottom->GetDims()[0]; b++) {
        for(int o = 0; o < out_channels; o++) {
          for(int x = 0, x_top = 0; x < bottom->GetDims()[2] && x_top < top->GetDims()[2]; x += stride, x_top += 1) {
            for(int y = 0, y_top = 0; y < bottom->GetDims()[1] && y_top < top->GetDims()[1]; y += stride, y_top += 1) {
              // batch idx b, output layer o, pixel (x, y)
              // top->at({b, y, x, o}) = 
              int idx[4] = {b, y, x, o};
              Dtype sum = 0.0;
              for(int c = 0; c < in_channels; c++) {
                for(int i = 0; i < kernel_height; i++) {
                  for(int j = 0; j < kernel_width; j++) {
                    // (n, hei, wid, channel),   // (hei, wid, input, output)
                    int b_idx[4] = {idx[0], idx[1]+i-int(kernel_height/2), idx[2]+j-int(kernel_width/2), c};
                    int t_idx[4] = {i, j, c, idx[3]};
                    sum += bottom->atPadding(b_idx) * W_->at(t_idx);
                  }
                }
              }
              int b_idx[4] = {0,0,0,0};
              sum += b_->at(b_idx);
              int t_idx[4] = {b, y_top, x_top, o};
              
              top->at(t_idx) = sum;
            }
          }
        }
      }
    }
  }

  // void Backward(Tensor& bottom, Tensor& top, Tensor& gradient) {}

  const size_t kernel_height;
  const size_t kernel_width;
  const size_t in_channels;
  const size_t out_channels;
  const size_t stride;

private:
  Tensor<Dtype>* W_;
  Tensor<Dtype>* b_;
  const Initializer<Dtype>* initializer_;
  void InitParams() {
    if (initializer_!=NULL) {
      initializer_->Initialize(W_, b_);
    } else {
      GaussianKernelInitializer<Dtype>((Dtype)5.0).Initialize(W_, b_, Session::GetSession()->gpu);
    }
  }
};


#endif  // CONV2D_LAYER_CUH_