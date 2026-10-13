#pragma once

#include "vector3.cuh"
#include <curand_kernel.h>

inline __device__ vector3 random_unit_vector(curandState* local_state) {
    double phi = curand_uniform_double(local_state) * 2.0 * PI;  // [0, 2π)
    double z = curand_uniform_double(local_state) * 2.0 - 1.0;   // [-1, 1)
    double r = sqrt(1.0 - z * z);
    return vector3(r * cos(phi), r * sin(phi), z);
}

inline __device__ vector3 random_unit_vector_in_disk(curandState* local_state, const vector3& normalVector) {
	double theta = curand_uniform_double(local_state) * 2 * PI;
	//sqrt(r)是为了使得点在圆盘上均匀分布
	double r = sqrt(curand_uniform_double(local_state));

	vector3 u = unit_vector(normalVector);

	vector3 v = cross(u, vector3(0, 1, 0));

	if (v.near_zero()) {
		v = cross(u, vector3(1, 0, 0));
	}

	return r * (cos(theta) * v + sin(theta) * cross(u, v));
}

inline __device__ vector3 reflect(const vector3& v, const vector3& n) {
	return v - 2 * dot(v, n) * n;
}

inline __device__ vector3 refract(const vector3& uv, const vector3& n, double etai_over_etat) {
	double cos_theta = fmin(dot(-uv, n), 1.0);
	vector3 r_out_perp = etai_over_etat * (uv + cos_theta * n);
	//为了防止全内反射造成报错，先加个绝对值
	vector3 r_out_parallel = -sqrt(fabs(1.0 - r_out_perp.length_squared())) * n;
	return r_out_perp + r_out_parallel;
}

inline __device__ double reflectance(double cosine, double refraction_index) {
	// Use Schlick's approximation for reflectance.
	auto r0 = (1 - refraction_index) / (1 + refraction_index);
	r0 = r0 * r0;
	return r0 + (1 - r0) * std::pow((1 - cosine), 5);
}

__device__ __host__ class Perlin {
public:
    __host__ Perlin() {
        for (int i = 0; i < point_count; i++) {
            randfloat[i] = random_double();
			randvec[i] = vector3(random_double(-1, 1), random_double(-1, 1), random_double(-1, 1));
        }

        perlin_generate_perm(perm_x);
        perlin_generate_perm(perm_y);
        perlin_generate_perm(perm_z);
    }

    __device__ __host__ double noise(const point3& p) const {
        double u = p.x() - floor(p.x());
        double v = p.y() - floor(p.y());
        double w = p.z() - floor(p.z());

        int i = int(floor(p.x()));
        int j = int(floor(p.y()));
        int k = int(floor(p.z()));

		vector3 vector[2][2][2];
		for (int di = 0; di < 2; di++) {
			for (int dj = 0; dj < 2; dj++) {
				for (int dk = 0; dk < 2; dk++) {
					vector[di][dj][dk] = randvec[perm_x[(i + di) & 255] ^ perm_y[(j + dj) & 255] ^ perm_z[(k + dk) & 255]];
				}
			}
		}

		double accum = 0.0;
		double weight_u = u * u * u * (u * (u * 6 - 15) + 10);
		double weight_v = v * v * v * (v * (v * 6 - 15) + 10);
		double weight_w = w * w * w * (w * (w * 6 - 15) + 10);

		for (int i = 0; i < 2; i++) {
			for (int j = 0; j < 2; j++) {
				for (int k = 0; k < 2; k++) {
					vector3 weight_v3(u - i, v - j, w - k);
					accum += ((i * weight_u + (1 - i) * (1 - weight_u)) *
						(j * weight_v + (1 - j) * (1 - weight_v)) *
						(k * weight_w + (1 - k) * (1 - weight_w))) *
						dot(vector[i][j][k], weight_v3);
				}
			}
		}

		return accum;
    }

private:
    static const int point_count = 256;
    double randfloat[point_count];
	vector3 randvec[point_count];
    int perm_x[point_count];
    int perm_y[point_count];
    int perm_z[point_count];

    __host__ static void perlin_generate_perm(int* p) {
        for (int i = 0; i < point_count; i++)
            p[i] = i;

        permute(p, point_count);
    }

    __host__ static void permute(int* p, int n) {
        for (int i = n - 1; i > 0; i--) {
            int target = rand() % (i + 1);
            int tmp = p[i];
            p[i] = p[target];
            p[target] = tmp;
        }
    }
};