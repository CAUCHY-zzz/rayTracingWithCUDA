#pragma once

#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <limits>

#undef max
#undef min

__device__ const double Infinity = std::numeric_limits<double>::infinity();
#define PI 3.1415926535897932385

__device__ class interval {
public:
    double min, max;
    __device__ __host__ interval() : min(+Infinity), max(-Infinity) {} // Default interval is empty
    __device__ __host__ interval(double min, double max) : min(min), max(max) {}
    __device__ __host__ double size() const {
        return max - min;
    }
    __device__ __host__ bool contains(double x) const {
        return min <= x && x <= max;
    }
    __device__ __host__ bool surrounds(double x) const {
        return min < x && x < max;
    }
    __device__ __host__ double clamp(double x) const {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }

    //避免使用静态变量或函数
    //__device__ static double clamp(double x, double min, double max) {
    //    if (x < min) return min;
    //    if (x > max) return max;
    //    return x;
    //}
};