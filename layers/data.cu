
#ifndef DATA_LAYER_CUH_
#define DATA_LAYER_CUH_

#include <assert.h>
#include <stdio.h>
#include <string>
#include <sstream>
#include <iostream>
#include "basics/layer.hpp"
#include "basics/tensor.cu"
#include "utils/bitmap_image.hpp"
#include "basics/session.hpp"

// TODO: implement prefetch data in CPU memory
// TODO: implement prefetch data in another thread of CPU
// TODO: implement CUDA kernel for backward()

#define BLOCKDIM 32


template <class Dtype>
class Data: public Layer<Dtype> {
public:
  Data(unsigned batch_size, char img_list_path[]):
       batch_size(batch_size), begin_(0) {
    std::string img_path;
    size_t lab;

    std::ifstream file(img_list_path);
    std::string tmp;
    while(std::getline(file, tmp)) {
      std::istringstream iss(tmp);
      iss >> img_path;
      img_list.push_back(img_path);
      iss >> lab;
      lab_list.push_back(lab);
    }
    num_data_ = lab_list.size();
    assert(num_data_ > 0);
    assert(num_data_ >= batch_size);
    bitmap_image img(img_list[0]);
    img_h = img.height();
    img_w = img.width();
  }

  ~Data() {}

  void Forward(Tensor<Dtype>* bottom, Tensor<Dtype>* top) {}
  std::vector<Tensor<Dtype>* > Forward(const std::vector<Tensor<Dtype> *> &bottom) {}
  std::vector<Tensor<Dtype>* > Forward();
  void Forward(vector<Tensor<Dtype>*> &bottom, vector<Tensor

  __host__ void FetchBatchData(Tensor<Dtype>*, Tensor<Dtype>*);

  // void Backward(Tensor& bottom, Tensor& top, Tensor& gradient) {}

  const size_t batch_size;
  std::vector<std::string> img_list;
  std::vector<size_t> lab_list;

  size_t img_h;
  size_t img_w;

private:
  size_t begin_;
  size_t end_;
  size_t num_data_;
//  size_t img_c;
};

template <class Dtype>
std::vector<Tensor<Dtype>* > Data<Dtype>::Forward() {
  end_ = begin_ + batch_size;
  if (end_ > num_data_) {
    begin_ = 0;
    end_ = begin_ + batch_size;
  }

  size_t dims_i[4] = {batch_size, img_h, img_w, 3};
  Tensor<Dtype>* top_i = Tensor<Dtype>::CreateTensorCPU(dims_i);

  size_t dims_l[4] = {batch_size, 1, 1, 1};
  Tensor<Dtype>* top_l = Tensor<Dtype>::CreateTensorCPU(dims_l);

  FetchBatchData(top_i, top_l);  
  if (Session::GetSession()->gpu) {
    Tensor<Dtype>* top_i_gpu = Tensor<Dtype>::TensorCPUtoGPU(top_i);
    Tensor<Dtype>* top_l_gpu = Tensor<Dtype>::TensorCPUtoGPU(top_l);
    delete top_i;
    delete top_l;
    top_i = top_i_gpu;
    top_l = top_l_gpu;
  }

  std::vector<Tensor<Dtype>* > top;
  top.push_back(top_i);
  top.push_back(top_l);

  return top;
}

template <class Dtype>
__host__ void Data<Dtype>::FetchBatchData(Tensor<Dtype>* top_i, Tensor<Dtype>* top_l) {
  bitmap_image* img;
  for (size_t i = 0; i < batch_size; ++i) {
    img = new bitmap_image(img_list[i+begin_]);
    top_l->at(i,0,0,0) = (Dtype) lab_list[i+begin_];
    for (size_t y = 0; y < img_h; ++y) {
      for (size_t x = 0; x < img_w; ++x) {
        top_i->at(i,y,x,0) = (Dtype) img->red_channel(x,y);
        top_i->at(i,y,x,1) = (Dtype) img->green_channel(x,y);
        top_i->at(i,y,x,2) = (Dtype) img->blue_channel(x,y);
      }
    }
    delete img;
  }
}

#endif  // DATA_LAYER_CUH_