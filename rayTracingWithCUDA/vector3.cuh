#pragma once

#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <cmath>
#include <vector>
#include "interval.cuh"

inline double random_double(double min = 0, double max = 1) {
	return min + (rand() % 0x7fff) / double(0x7fff) * (max - min);
}

__device__ __host__ class vector3 {
public:
	double e[3];

	__device__ __host__ vector3() {
		e[0] = 0;
		e[1] = 0;
		e[2] = 0;
	}

	__device__ __host__ vector3(double e0, double e1, double e2) {
		e[0] = e0;
		e[1] = e1;
		e[2] = e2;
	}

	__device__ __host__ double x() const { return e[0]; }
	__device__ __host__ double y() const { return e[1]; }
	__device__ __host__ double z() const { return e[2]; }

	__device__ __host__ vector3 operator-() const { return vector3(-e[0], -e[1], -e[2]); }
	__device__ __host__ double operator[](int i) const { return e[i]; }
	__device__ __host__ double& operator[](int i) { return e[i]; }

	__device__ __host__ vector3& operator+=(const vector3& v) {
		e[0] += v.e[0];
		e[1] += v.e[1];
		e[2] += v.e[2];
		return *this;
	}

	__device__ __host__ vector3& operator-=(const vector3& v) {
		return *this += -v;
	}

	__device__ __host__ vector3& operator*=(const double t) {
		e[0] *= t;
		e[1] *= t;
		e[2] *= t;
		return *this;
	}

	__device__ __host__ vector3& operator/=(const double t) {
		return *this *= 1 / t;
	}

	__device__ __host__ double length() const {
		return sqrt(length_squared());
	}

	__device__ __host__ double length_squared() const {
		return e[0] * e[0] + e[1] * e[1] + e[2] * e[2];
	}

	__device__ __host__ vector3 unit_vecttor() {
		*this /= length();
		return *this;
	}

	__device__ __host__ bool near_zero() {
		const double s = 1e-8;
		return (fabs(e[0]) < s) && (fabs(e[1]) < s) && (fabs(e[2]) < s);
	}

	static __host__ vector3 random(double min = 0, double max = 1) {
		return vector3(random_double(min, max), random_double(min, max), random_double(min, max));
	}
};

__device__ __host__ inline vector3 operator+(const vector3& u, const vector3& v) {
	return vector3(u.e[0] + v.e[0], u.e[1] + v.e[1], u.e[2] + v.e[2]);
}

__device__ __host__ inline vector3 operator-(const vector3& u, const vector3& v) {
	return vector3(u.e[0] - v.e[0], u.e[1] - v.e[1], u.e[2] - v.e[2]);
}

__device__ __host__ inline vector3 operator*(const vector3& u, const vector3& v) {
	return vector3(u.e[0] * v.e[0], u.e[1] * v.e[1], u.e[2] * v.e[2]);
}

__device__ __host__ inline vector3 operator*(double t, const vector3& v) {
	return vector3(t * v.e[0], t * v.e[1], t * v.e[2]);
}

__device__ __host__ inline vector3 operator*(const vector3& v, double t) {
	return t * v;
}

__device__ __host__ inline vector3 operator/(const vector3& v, double t) {
	return (1 / t) * v;
}

__device__ __host__ inline double dot(const vector3& u, const vector3& v) {
	return u.e[0] * v.e[0]
		+ u.e[1] * v.e[1]
		+ u.e[2] * v.e[2];
}
__device__ __host__ inline vector3 cross(const vector3& u, const vector3& v) {
	return vector3(u.e[1] * v.e[2] - u.e[2] * v.e[1],
		u.e[2] * v.e[0] - u.e[0] * v.e[2],
		u.e[0] * v.e[1] - u.e[1] * v.e[0]);
}

__device__ __host__ inline vector3 unit_vector(const vector3& v) {
	return v / v.length();
}

__device__ __host__ class Color : public vector3 {
public:
	__device__ __host__ Color() : vector3() {}
	__device__ __host__ Color(double e0, double e1, double e2) : vector3(e0, e1, e2) {}
	__device__ __host__ Color(const vector3& v) : vector3(v) {}

	__device__ __host__ uint8_t r() const {
		const interval color_interval(0, 1);
		double gamma_r = sqrt(color_interval.clamp(e[0]));
		return int(255.999 * gamma_r);
	}
	__device__ __host__ uint8_t g() const {
		const interval color_interval(0, 1);
		double gamma_g = sqrt(color_interval.clamp(e[1]));
		return int(255.999 * gamma_g);
	}
	__device__ __host__ uint8_t b() const {
		const interval color_interval(0, 1);
		double gamma_b = sqrt(color_interval.clamp(e[2]));
		return int(255.999 * gamma_b);
	}

	__device__ __host__ uchar4 toRGB() const {
		uchar4 RGBcolor;
		RGBcolor.w = 255;
		RGBcolor.z = r();
		RGBcolor.y = g();
		RGBcolor.x = b();
		return RGBcolor;
	}

	__device__ __host__ Color& operator+=(const Color& v) {
		e[0] += v.e[0];
		e[1] += v.e[1];
		e[2] += v.e[2];
		return *this;
	}

	__device__ __host__ Color& operator-=(const Color& v) {
		return *this += -v;
	}

	__device__ __host__ Color& operator*=(const Color& v) {
		e[0] *= v.e[0];
		e[1] *= v.e[1];
		e[2] *= v.e[2];
		return *this;
	}

	__device__ __host__ Color& operator*=(const double t) {
		e[0] *= t;
		e[1] *= t;
		e[2] *= t;
		return *this;
	}

	__device__ __host__ Color& operator/=(const double t) {
		return *this *= 1 / t;
	}

	__device__ __host__ Color& operator/=(const Color& v) {
		e[0] /= v.e[0];
		e[1] /= v.e[1];
		e[2] /= v.e[2];
		return *this;
	}

	__device__ __host__ Color& operator=(const vector3& v) {
		e[0] = v.e[0];
		e[1] = v.e[1];
		e[2] = v.e[2];
		return *this;
	}

	__device__ __host__ Color& operator=(const Color& v) {
		e[0] = v.e[0];
		e[1] = v.e[1];
		e[2] = v.e[2];
		return *this;
	}
};

__device__ __host__ inline Color operator+(const Color& u, const Color& v) {
	return Color(u.e[0] + v.e[0], u.e[1] + v.e[1], u.e[2] + v.e[2]);
}

__device__ __host__ inline Color operator-(const Color& u, const Color& v) {
	return Color(u.e[0] - v.e[0], u.e[1] - v.e[1], u.e[2] - v.e[2]);
}

__device__ __host__ inline Color operator*(const Color& u, const Color& v) {
	return Color(u.e[0] * v.e[0], u.e[1] * v.e[1], u.e[2] * v.e[2]);
}

__device__ __host__ inline Color operator*(double t, const Color& v) {
	return Color(t * v.e[0], t * v.e[1], t * v.e[2]);
}

__device__ __host__ inline Color operator*(const Color& v, double t) {
	return t * v;
}

__device__ __host__ inline Color operator/(const Color& v, double t) {
	return (1 / t) * v;
}

__device__ __host__ inline Color operator/(const Color& u, const Color& v) {
	return Color(u.e[0] / v.e[0], u.e[1] / v.e[1], u.e[2] / v.e[2]);
}

using point3 = vector3;

//----------------------------------------------------------------------------//
//                              host matrix                                   //
//----------------------------------------------------------------------------//

inline vector3 operator* (const std::vector<vector3> Matrix, const vector3 v) {
	return vector3(
		v.x() * Matrix[0][0] + v.y() * Matrix[0][1] + v.z() * Matrix[0][2],
		v.x() * Matrix[1][0] + v.y() * Matrix[1][1] + v.z() * Matrix[1][2],
		v.x() * Matrix[2][0] + v.y() * Matrix[2][1] + v.z() * Matrix[2][2]
	);
}

inline std::vector<vector3> matrix33Mult(const std::vector<vector3> Matrix_A, const std::vector<vector3> Matrix_B) {
	std::vector<vector3> result = {
		{0, 0, 0},
		{0, 0, 0},
		{0, 0, 0}
	};
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			result[i][j] = Matrix_A[i][0] * Matrix_B[0][j] + Matrix_A[i][1] * Matrix_B[1][j] + Matrix_A[i][2] * Matrix_B[2][j];
		}
	}
	return result;
}

inline vector3 Roll(vector3 vector, double r, double p, double y) {
	//³õÊ¼»¯Ðý×ª¾ØÕó
	std::vector<vector3> Rx = {
		{1, 0, 0},
		{0, cos(r), -sin(r)},
		{0, sin(r), cos(r)}
	};

	std::vector<vector3> Ry = {
		{cos(p), 0, sin(p)},
		{0, 1, 0},
		{-sin(p), 0, cos(p)}
	};

	std::vector<vector3> Rz = {
		{cos(y), -sin(y), 0},
		{sin(y), cos(y), 0},
		{0, 0, 1}
	};

	std::vector<vector3> rollMatrix = matrix33Mult(matrix33Mult(Rz, Ry), Rx);

	return rollMatrix * vector;
}