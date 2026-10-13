#pragma once

#ifndef RAY_HIT_H
#define RAY_HIT_H

#include "vector3.cuh"
#include "rayVector.cuh"
#include "createVideo.h"
#include <algorithm>

class Material;
class Hittable;

class Ray {
public:
	point3 originPoint;
	vector3 directionVector;

	__device__ __host__ Ray() {}
	__device__ __host__ Ray(const vector3& origin, const vector3& direction)
		: originPoint(origin), directionVector(direction) {}

	__device__ __host__ point3 origin() const { return originPoint; }
	__device__ __host__ vector3 direction() const { return directionVector; }

	__device__ __host__ point3 at(double t) const {
		return originPoint + t * directionVector;
	}
};

class HitRecord {
public:
	point3 hitPoint;
	vector3 normalVector;
	double t;
	bool isFrontFace;
	Material* mat_ptr;
	double u, v;

	__device__ void getHitRecord(const Ray& ray, const double t, const vector3& outwardNormalVector, Material* mat_ptr, double u, double v) {
		hitPoint = ray.at(t);
		this->t = t;
		this->mat_ptr = mat_ptr;

		if (u < 0 || v < 0 || u >= 1.0 || v >= 1.0) {
			u = 0;
			v = 0;
		}
		this->u = u;
		this->v = v;

		setNormalVector(ray, outwardNormalVector);
	}

	__device__ void setNormalVector(const Ray& ray, const vector3& outwardNormalVector) {
		//由于 ray.direction() 是从眼点发出的，故 < 0 才是光线和外法线同侧
		isFrontFace = dot(ray.direction(), outwardNormalVector) < 0;
		normalVector = isFrontFace ? outwardNormalVector : -outwardNormalVector;
		normalVector.unit_vecttor();
	}
};

//-----------------------------------------------------------------------------------------------//
//                                          Texture                                              //
//-----------------------------------------------------------------------------------------------//

struct Texture;
__device__ __host__ class boardTexture {
public:
	double scale;
	Texture* oddTexture;
	Texture* evenTexture;
	//交给 Texture 实现
	//__device__ Color value(const HitRecord& record) const;
};

__device__ __host__ class ImageTexture {
public:
	unsigned char* data;
	int width;
	int height;

	__device__ __host__ ImageTexture() {
		data = nullptr;
		width = 0;
		height = 0;
	}

	//图像数据交由
	__device__ __host__ ~ImageTexture() = default;

	__device__ Color value(const HitRecord& record) const {
		int i = static_cast<int>(record.u * width);
		int j = static_cast<int>(record.v * abs(height));

		return Color(data[4 * i + 4 * width * j + 2] / 255.0, data[4 * i + 4 * width * j + 1] / 255.0, data[4 * i + 4 * width * j + 0] / 255.0);
	}
};

__device__ __host__ class noiseTexture {
public:
	double scale = 1;
	int depth = 0; //噪声深度
	Perlin* perlin;

	__device__ __host__ noiseTexture() = default;

	__device__ Color value(const HitRecord& record) const {
		if (depth == 0) {
			return Color(1, 1, 1) * (perlin->noise(record.hitPoint / scale) / 2 + 0.5);
		}

		double noise = 0.0;
		double weight = 1.0;
		point3 tempP = record.hitPoint / scale;
		for (int i = 0; i < depth; i++) {
			noise += weight * perlin->noise(tempP);
			weight *= 0.5;
			tempP *= 2;
		}

		return Color(1, 1, 1) * abs(noise);
	}
};

enum textureType { IMAGE, SOLID, BOARD, NOISE };
struct Texture {
	textureType active_type;  // 类型标签
	Color albedo;
	union {
		ImageTexture image;
		boardTexture board;
		noiseTexture noise;
	};

	__device__ __host__ Texture() {
		active_type = SOLID;
		albedo = Color(0, 0, 0);
	}

	__device__ __host__ ~Texture() {
		switch (active_type) {
		case IMAGE:
			image.~ImageTexture();
			break;
		case SOLID:
			break;
		case BOARD:
			board.evenTexture->~Texture();
			board.oddTexture->~Texture();
			break;
		case NOISE:
			noise.perlin->~Perlin();
			break;
		}
	}

	//由于涉及递归定义，故在此实现
	__device__ Color boardValue(const HitRecord& record) const {
		if (active_type != BOARD) {
			return Color(0, 0, 0);
		}

		auto xInteger = int(std::floor(record.hitPoint.x() / board.scale));
		auto yInteger = int(std::floor(record.hitPoint.y() / board.scale));
		auto zInteger = int(std::floor(record.hitPoint.z() / board.scale));

		if ((xInteger + yInteger + zInteger) % 2 == 0) {
			return board.evenTexture->value(record);
		}
		else {
			return board.oddTexture->value(record);
		}
	}

	__device__ Color value(const HitRecord& record) const {
		switch (active_type) {
		case IMAGE:
			return albedo * image.value(record);
		case SOLID:
			return albedo;
		case BOARD:
			return albedo * boardValue(record);
		case NOISE:
			return albedo * noise.value(record);
		}
		return Color(0, 0, 0);
	}
};

//-----------------------------------------------------------------------------------------------//
//                                         Material                                              //
//-----------------------------------------------------------------------------------------------//

__device__ __host__ class Lambertian {
public:
	double fuzzForSimpleLight;
	double nForSimpleLight = 2;
	Texture* texture_ptr;
	Color emitColor = Color(0, 0, 0);

	__device__ __host__ Lambertian() {
		cudaMallocManaged(&texture_ptr, sizeof(Texture));
		texture_ptr->active_type = SOLID;
		texture_ptr->albedo = Color(0, 0, 0);
		fuzzForSimpleLight = 0;
	}

	__device__ __host__ Lambertian(const Color& a) {
		//albedo = a;
		cudaMallocManaged(&texture_ptr, sizeof(Texture));
		texture_ptr->active_type = SOLID;
		texture_ptr->albedo = a;
		fuzzForSimpleLight = 0;
	}

	__device__ __host__ Lambertian(const Color& a, double fuzzForSimpleLight) {
		cudaMallocManaged(&texture_ptr, sizeof(Texture));
		texture_ptr->active_type = SOLID;
		texture_ptr->albedo = a;
		this->fuzzForSimpleLight = fuzzForSimpleLight;
	}

	__device__ __host__ Lambertian(const Lambertian& other) {
		*this = other;
	}

	__device__ __host__ Lambertian& operator=(const Lambertian& other) {
		//防止浅拷贝
		if (this != &other) {
			if (texture_ptr != nullptr) {
				//图像纹理数据已交由 imageTextureDataCache 统一管理
				//if (texture_ptr->active_type == textureType::IMAGE) {
				//	cudaFree(texture_ptr->image.data);
				//}
				cudaFree(texture_ptr);
			}
			cudaMallocManaged(&texture_ptr, sizeof(Texture));
			cudaMemcpy(texture_ptr, &other.texture_ptr, sizeof(Texture), cudaMemcpyDeviceToDevice);
			fuzzForSimpleLight = other.fuzzForSimpleLight;
			emitColor = other.emitColor;
		}
		return *this;
	}

	__device__ __host__ ~Lambertian() {
		cudaFree(texture_ptr);
	}

	__device__ bool scatter(curandState* local_state, const Ray& r_in, const HitRecord& rec, Color& attenuation, Ray& scattered) const {
		vector3 scatter_direction = rec.normalVector + random_unit_vector(local_state);
		if (scatter_direction.near_zero())
			scatter_direction = rec.normalVector;
		scattered = Ray(rec.hitPoint, scatter_direction);
		attenuation = (texture_ptr == nullptr ? Color(0, 0, 0) : texture_ptr->value(rec));
		return true;
	}

	__device__ Color emit(const HitRecord& rec) const {
		return texture_ptr->value(rec) * emitColor;
	}
};

__device__ __host__ class Metal {
public:
	double fuzz;
	Texture* texture_ptr;
	Color emitColor = Color(0, 0, 0);

	__device__ __host__ Metal() {
		cudaMallocManaged(&texture_ptr, sizeof(Texture));
		texture_ptr->active_type = SOLID;
		texture_ptr->albedo = Color(0.5, 0.5, 0.5);
		fuzz = 0;
	}

	__device__ __host__ Metal(const Color& a, double f) : fuzz(f < 1 ? f : 1) {
		cudaMallocManaged(&texture_ptr, sizeof(Texture));
		texture_ptr->active_type = SOLID;
		texture_ptr->albedo = a;
	}

	__device__ __host__ Metal(const Metal& other) {
		*this = other;
	}

	__device__ __host__ Metal& operator=(const Metal& other) {
		//防止浅拷贝
		if (this != &other) {
			if (texture_ptr != nullptr) {
				cudaFree(texture_ptr);
			}
			cudaMallocManaged(&texture_ptr, sizeof(Texture));
			cudaMemcpy(texture_ptr, &other.texture_ptr, sizeof(Texture), cudaMemcpyDeviceToDevice);
		}
		return *this;
	}

	__device__ __host__ ~Metal() {
		cudaFree(texture_ptr);
	}

	__device__ bool scatter(curandState* local_state, const Ray& r_in, const HitRecord& rec, Color& attenuation, Ray& scattered) const {
		//归一化
		vector3 reflected = reflect(unit_vector(r_in.direction()), rec.normalVector);
		scattered = Ray(rec.hitPoint, reflected + fuzz * random_unit_vector(local_state));
		attenuation = (texture_ptr == nullptr ? Color(0, 0, 0) : texture_ptr->value(rec));
		return dot(scattered.direction(), rec.normalVector) > 0;
	}

	__device__ Color emit(const HitRecord& rec) const {
		return texture_ptr->value(rec) * emitColor;
	}
};

__device__ __host__ class Glass{
public:
	//折射率
	Texture* texture_ptr;
	double ref_idx;
	Color emitColor = Color(0, 0, 0);

	__device__ __host__ Glass() {
		cudaMallocManaged(&texture_ptr, sizeof(Texture));
		texture_ptr->active_type = SOLID;
		texture_ptr->albedo = Color(0.5, 0.5, 0.5);
		ref_idx = 1.5;
	}

	__device__ __host__ Glass(const Color& a, double ri) : ref_idx(ri) {
		cudaMallocManaged(&texture_ptr, sizeof(Texture));
		texture_ptr->active_type = SOLID;
		texture_ptr->albedo = a;
	}

	__device__ __host__ Glass(const Glass& other) {
		*this = other;
	}

	__device__ __host__ Glass& operator=(const Glass& other) {
		//防止浅拷贝
		if (this != &other) {
			if (texture_ptr != nullptr) {
				cudaFree(texture_ptr);
			}
			cudaMallocManaged(&texture_ptr, sizeof(Texture));
			cudaMemcpy(texture_ptr, &other.texture_ptr, sizeof(Texture), cudaMemcpyDeviceToDevice);
		}
		return *this;
	}

	__device__ __host__ ~Glass() {
		cudaFree(texture_ptr);
	}

	__device__ bool scatter(curandState* local_state, const Ray& r_in, const HitRecord& rec, Color& attenuation, Ray& scattered) const {
		//判断进出介质
		double ri = rec.isFrontFace ? (1.0 / ref_idx) : ref_idx;
		vector3 unit_direction = unit_vector(r_in.direction());

		double cos_theta = fmin(dot(-unit_direction, rec.normalVector), 1.0);
		double sin_theta = sqrt(1.0 - cos_theta * cos_theta);
		bool cantRefract = sin_theta * ri > 1;

		vector3 direction;

		if (cantRefract || reflectance(cos_theta, ri) > curand_uniform_double(local_state)) {
			direction = reflect(unit_direction, rec.normalVector);
		}
		else
		{
			direction = refract(unit_direction, rec.normalVector, ri);
		}

		scattered = Ray(rec.hitPoint, direction);
		attenuation = (texture_ptr == nullptr ? Color(0, 0, 0) : texture_ptr->value(rec));
		return true;
	}

	__device__ Color emit(const HitRecord& rec) const {
		return texture_ptr->value(rec) * emitColor;
	}
};

enum materialType { LAMBERTIAN, METAL, GLASS };
struct Material {
	materialType active_type;  // 类型标签
	union {
		Lambertian lambertian;
		Metal metal;
		Glass glass;
	};

	__device__ __host__ Material() {}

	__device__ __host__ Material(const materialType type, const Color& a) : active_type(type) {
		if (active_type == METAL) metal = Metal(a, 0.0);
		else if (active_type == GLASS) glass = Glass(a, 1.5);
		else if (active_type == LAMBERTIAN) lambertian = Lambertian(a);
	}

	__device__ __host__ Material(const materialType type, const Color& a, double f) : active_type(type) {
		if (active_type == METAL) metal = Metal(a, f);
		else if (active_type == GLASS) glass = Glass(a, f);
		else if (active_type == LAMBERTIAN) lambertian = Lambertian(a, f);
	}

	__device__ __host__ Material(const Material& other) {
		*this = other;
	}

	__device__ __host__ Material& operator=(const Material& other) {
		//防止浅拷贝
		if (this != &other) {
			if (active_type == LAMBERTIAN) lambertian.~Lambertian();
			else if (active_type == METAL) metal.~Metal();
			else if (active_type == GLASS) glass.~Glass();

			active_type = other.active_type;
			if (active_type == METAL) metal = other.metal;
			else if (active_type == GLASS) glass = other.glass;
			else if (active_type == LAMBERTIAN) lambertian = other.lambertian;
		}
		return *this;
	}

	__device__ __host__ ~Material() {
		if (active_type == LAMBERTIAN) lambertian.~lambertian();
		else if (active_type == METAL) metal.~Metal();
		else if (active_type == GLASS) glass.~Glass();
	}

	__device__ bool scatter(curandState* local_state, const Ray& r_in, const HitRecord& rec, Color& attenuation, Ray& scattered) const {
		switch (active_type) {
		case LAMBERTIAN:
			return lambertian.scatter(local_state, r_in, rec, attenuation, scattered);
		case METAL:
			return metal.scatter(local_state, r_in, rec, attenuation, scattered);
		case GLASS:
			return glass.scatter(local_state, r_in, rec, attenuation, scattered);
		}
		return false;
	}

	__device__ Color emit(const HitRecord& rec) {
		switch (active_type) {
		case LAMBERTIAN:
			return lambertian.emit(rec);
		case METAL:
			return metal.emit(rec);
		case GLASS:
			return glass.emit(rec);
		}
		return Color(0, 0, 0);
	}

	__device__ Color getAlbedo() const {
		switch (active_type) {
		case LAMBERTIAN:
			return lambertian.texture_ptr->albedo;
		case METAL:
			return metal.texture_ptr->albedo;
		case GLASS:
			return glass.texture_ptr->albedo;
		}
		return Color(0, 0, 0);
	}

	__device__ Color getTextureColor(const HitRecord& record) const {
		switch (active_type) {
		case LAMBERTIAN:
			return lambertian.texture_ptr->value(record);
		case METAL:
			return metal.texture_ptr->value(record);
		case GLASS:
			return glass.texture_ptr->value(record);
		}
		return Color(0, 0, 0);
	}
};


//-----------------------------------------------------------------------------------------------//
//                                         Hittable                                              //
//-----------------------------------------------------------------------------------------------//

struct Box {
	point3 min;
	point3 max;

	Box() = default;
	Box(point3 min, point3 max) : min(min), max(max) {};
	__host__ Box& operator+=(const Box& box) {
		for (int i = 0; i < 3; i++) {
			min.e[i] = fmin(min.e[i], box.min.e[i]);
			max.e[i] = fmax(max.e[i], box.max.e[i]);
		}
		return *this;
	}
};

__device__ __host__ class Ball {
public:
	point3 center;
	double R;
	Material* mat_ptr;

	__device__ __host__ Ball() {
		center = point3(0, 0, -1);
		R = 0.5;
	}
	__device__ __host__ Ball(point3 center, double R, Material* mat_ptr) : center(center), R(abs(R)), mat_ptr(mat_ptr) {}

	__device__ bool hit(const Ray& r, interval ray_t, HitRecord& record) const {
		vector3 oc = r.origin() - center;
		double a = r.direction().length_squared();
		double half_b = dot(oc, r.direction());
		double c = oc.length_squared() - R * R;

		double discriminant = half_b * half_b - a * c;
		if (discriminant < 0) return false;
		double sqrtd = sqrt(discriminant);

		// Find the nearest root that lies in the acceptable range.
		double root = (-half_b - sqrtd) / a;
		if (!ray_t.surrounds(root)) {
			root = (-half_b + sqrtd) / a;
			if (!ray_t.surrounds(root))
				return false;
		}

		vector3 outwardNormalVector = (r.at(root) - center).unit_vecttor();

		double h = asin(outwardNormalVector.y()) + PI / 2;
		double theta = atan2(outwardNormalVector.x(), outwardNormalVector.z()) + PI;
		double u = theta / (2 * PI);
		double v = h / PI;
		record.getHitRecord(r, root, outwardNormalVector, mat_ptr, u, v);

		return true;
	}

	__host__ Box getBbox() {
		return Box(center - vector3(R, R, R), center + vector3(R, R, R));
	}
};

__device__ __host__ class Triangle {
public:
	point3 p0, p1, p2;
	//法向量
	vector3 normalVector;
	vector3 Us = { 0, 1, 0 };
	vector3 Vs = { 0, 0, 1 };
	Material* mat_ptr;
	

	__device__ __host__ Triangle() {
		p0 = point3(0, 0, -1);
		p1 = point3(1, 0, -1);
		p2 = point3(0, 1, -1);
	}

	__device__ __host__ Triangle(point3 p0, point3 p1, point3 p2, Material* mat_ptr) : p0(p0), p1(p1), p2(p2), mat_ptr(mat_ptr) {
		normalVector = cross(p1 - p0, p2 - p0).unit_vecttor();
	}

	__device__ __host__ Triangle(point3 p0, point3 p1, point3 p2, Material* mat_ptr, vector3 Us, vector3 Vs) : p0(p0), p1(p1), p2(p2), mat_ptr(mat_ptr), Us(Us), Vs(Vs) {
		normalVector = cross(p1 - p0, p2 - p0).unit_vecttor();
	}

	__device__ bool hit(const Ray& r, interval ray_t, HitRecord& record) const {
		vector3 edge1 = p1 - p0;
		vector3 edge2 = p2 - p0;

		vector3 h = cross(r.direction(), edge2);
		double a = dot(edge1, h);
		if (a > -0.00001 && a < 0.00001) return false; //平行
		double f = 1.0 / a;
		vector3 s = r.origin() - p0;
		double u = f * dot(s, h);
		if (u < 0.0 || u > 1.0) return false;
		vector3 q = cross(s, edge1);
		double v = f * dot(r.direction(), q);
		if (v < 0.0 || u + v > 1.0) return false;
		double t = f * dot(edge2, q);
		if (t > ray_t.min && t < ray_t.max) {
			double tempU = Us.e[0] + u * (Us.e[1] - Us.e[0]) + v * (Us.e[2] - Us.e[0]);
			double tempV = Vs.e[0] + u * (Vs.e[1] - Vs.e[0]) + v * (Vs.e[2] - Vs.e[0]);
			record.getHitRecord(r, t, normalVector, mat_ptr, tempU, tempV);
			return true;
		}
		return false;
	}

	__host__ Box getBox() {
		point3 min;
		point3 max;

		for (int i = 0; i < 3; i++) {
			min.e[i] = std::min({ p0.e[i], p1.e[i], p2.e[i] });
			max.e[i] = std::max({ p0.e[i], p1.e[i], p2.e[i] });
		}

		return Box(min, max);
	}
};

//圆柱（可倾斜）
__device__ __host__ class Cylinder {
public:
	point3 baseCenter; // 圆柱底部中心点
	point3 topCenter; // 圆柱顶部中心点
	double radius; // 圆柱半径
	vector3 normalVector; // 圆法向量（垂直于底面圆）
	Material* mat_ptr; // 材质指针

	__device__ __host__ Cylinder() {
		baseCenter = point3(0, 0, -1);
		topCenter = point3(0, 0, 1);
		radius = 0.5;
		normalVector = vector3(0, 1, 0);
	}

	__device__ __host__ Cylinder(point3 baseCenter, point3 topCenter, double radius, Material* mat_ptr) 
		: baseCenter(baseCenter), topCenter(topCenter), radius(radius), mat_ptr(mat_ptr) {
		normalVector = (topCenter - baseCenter).unit_vecttor();
		if(dot(normalVector, topCenter - baseCenter) < 0) {
			normalVector = -normalVector; // 确保法向量指向上方
		}
	}

	__device__ __host__ Cylinder(point3 baseCenter, point3 topCenter, double radius, vector3 normalVector, Material* mat_ptr) 
		: baseCenter(baseCenter), topCenter(topCenter), radius(radius), mat_ptr(mat_ptr), normalVector(normalVector.unit_vecttor()) {
		if (dot(normalVector, topCenter - baseCenter) < 0) {
			this->normalVector = -this->normalVector; // 确保法向量指向上方
		}
	}

	__device__ bool hit(const Ray& r, interval ray_t, HitRecord& record) const {
		vector3 outwardNormalVector;

		vector3 OO_ = topCenter - baseCenter; // 圆柱的高度向量
		OO_ = OO_ / dot(normalVector, OO_); // z轴方向归一化高度向量
		vector3 OC = r.origin() - baseCenter; // 光线起点到底面圆心的向量

		double t = -1;
		double tempT = -1;
		int baseHitFlag = 0;
		//与底面圆的交点
		//光线与底面圆不平行
		if (dot(r.direction(), normalVector) != 0) {
			tempT = -(dot(OC, normalVector) / dot(r.direction(), normalVector));
			if((r.at(tempT) - baseCenter).length() <= radius) {
				if(ray_t.surrounds(tempT)) {
					ray_t.max = tempT;
					t = tempT;
					baseHitFlag = 1;
				}
			}
			tempT = -(dot(r.origin() - topCenter, normalVector) / dot(r.direction(), normalVector));
			if((r.at(tempT) - topCenter).length() <= radius) {
				if(ray_t.surrounds(tempT)) {
					ray_t.max = tempT;
					t = tempT;
					baseHitFlag = 2;
				}
			}
		}

		//光线与圆柱侧面交点
		// OX = OC + tv, |OX - (OX*n)OO'| = R
		vector3 v1 = OC - dot(OC, normalVector) * OO_;
		vector3 v2 = r.direction() - dot(r.direction(), normalVector) * OO_;
		double v11 = dot(v1, v1);
		double v12 = dot(v1, v2);
		double v22 = dot(v2, v2);
		if (!v2.near_zero()) {
			double Delta = v12 * v12 - v22 * (v11 - radius * radius);
			if (Delta == 0) {
				tempT = -v12 / v22;
				if (ray_t.surrounds(tempT) && dot(r.at(tempT) - baseCenter, normalVector) > 0 && dot(r.at(tempT) - topCenter, normalVector) < 0) {
					t = tempT;
					vector3 tempV = v1 + t * v2;
					outwardNormalVector = tempV - dot(OO_, tempV) * OO_ / OO_.length_squared();
					record.getHitRecord(r, t, outwardNormalVector, mat_ptr, 0, 0);
					return true;
				}
			}
			else if (Delta > 0) {
				tempT = (sqrt(Delta) - v12) / v22;
				bool hitFlag = false;
				if (ray_t.surrounds(tempT) && dot(r.at(tempT) - baseCenter, normalVector) > 0 && dot(r.at(tempT) - topCenter, normalVector) < 0) {
					t = tempT;
					hitFlag = true;
				}
				tempT = -(sqrt(Delta) + v12) / v22;
				if (ray_t.surrounds(tempT) && dot(r.at(tempT) - baseCenter, normalVector) > 0 && dot(r.at(tempT) - topCenter, normalVector) < 0) {
					t = tempT;
					vector3 tempV = v1 + t * v2;
					outwardNormalVector = tempV - dot(OO_, tempV) * OO_/OO_.length_squared();
					record.getHitRecord(r, t, outwardNormalVector, mat_ptr, 0, 0);
					return true;
				}
				if (hitFlag) {
					vector3 tempV = v1 + t * v2;
					outwardNormalVector = tempV - dot(OO_, tempV) * OO_ / OO_.length_squared();
					record.getHitRecord(r, t, outwardNormalVector, mat_ptr, 0, 0);
					return true;
				}
			}
		}

		if (baseHitFlag != 0) {
			if (baseHitFlag == 1) {
				outwardNormalVector = -normalVector;
			}
			else {
				outwardNormalVector = normalVector;
			}
			record.getHitRecord(r, t, outwardNormalVector, mat_ptr, 0, 0);
			return true;
		}
		return false;
	}

	__host__ Box getBox() {
		Box baseBox = Box(baseCenter - vector3(radius, radius, radius), baseCenter + vector3(radius, radius, radius));
		Box topBox = Box(topCenter - vector3(radius, radius, radius), topCenter + vector3(radius, radius, radius));
		
		point3 min, max;
		for (int i = 0; i < 3; i++) {
			min.e[i] = std::min({ baseBox.min.e[i], topBox.min.e[i]});
			max.e[i] = std::max({ baseBox.max.e[i], topBox.max.e[i]});
		}
		return Box(min, max);
	}
};

//未完成的贝塞尔曲面
__device__ __host__ class BezierSurface {
public:
	point3* controlPoints; // 4x4 控制点
	int rows;
	int cols;
	Material* mat_ptr;

	__device__ __host__ BezierSurface() {
		point3 temp[16] = {
			{0,0,0},  {0,0,-1},  {0,0,-2},  {0,0,-3},
			{1,0,0},  {1,2,-1},  {1,2,-2},  {1,0,-3},
			{2,0,0},  {2,2,-1},  {2,2,-2},  {2,0,-3},
			{3,0,0},  {3,0,-1},  {3,0,-2},  {3,0,-3}
		};
		cudaMallocManaged(&controlPoints, sizeof(point3) * 16);
		cudaMemcpy(controlPoints, temp, sizeof(point3) * 16, cudaMemcpyHostToDevice);
		rows = 4;
		cols = 4;
	}

	__device__ __host__ BezierSurface(point3* points, int rows, int cols, Material* mat_ptr) : rows(rows), cols(cols), mat_ptr(mat_ptr) {
		cudaMallocManaged(&controlPoints, sizeof(point3) * rows * cols);
		cudaMemcpy(controlPoints, points, sizeof(point3) * rows * cols, cudaMemcpyHostToDevice);
	}

	struct boxCode {
		// max 00000000 00000000 | min 00000000 00000000
		unsigned int rowCode;
		unsigned int colCode;

		boxCode() : rowCode(0xffff0000), colCode(0xffff0000) {}
		boxCode(unsigned int rowCode, unsigned int colCode, int size) : rowCode(rowCode), colCode(colCode) {}
		__device__ void decodeBox(double& min_u, double& max_u, double& min_v, double& max_v) const {
			min_u = (rowCode & 0xFFFF) / 65535.0;
			max_u = ((rowCode >> 16) & 0xFFFF) / 65535.0;
			min_v = (colCode & 0xFFFF) / 65535.0;
			max_v = ((colCode >> 16) & 0xFFFF) / 65535.0;
		}
	};

	__device__ bool hit(const Ray& r, interval ray_t, HitRecord& record) const {
		const int MAX_STACK_DEPTH = 40;//十层四叉树
		boxCode stack[MAX_STACK_DEPTH];

		int stack_ptr = 0; // 栈顶指针（下一个空闲位置）
		stack[stack_ptr++] = boxCode(0xffff0000, 0xffff0000, 0); // 压入根节点

		return false;
	}

	__host__ Box getBox() {
		point3 min;
		point3 max;

		for (int i = 0; i < rows * cols; i++) {
			min.e[0] = std::min(min.e[0], controlPoints[i].e[0]);
			min.e[1] = std::min(min.e[1], controlPoints[i].e[1]);
			min.e[2] = std::min(min.e[2], controlPoints[i].e[2]);

			max.e[0] = std::max(max.e[0], controlPoints[i].e[0]);
			max.e[1] = std::max(max.e[1], controlPoints[i].e[1]);
			max.e[2] = std::max(max.e[2], controlPoints[i].e[2]);
		}

		return Box(min, max);
	}
};

// Hittable 作为通用接口
// 由于CUDA不支持虚函数，故使用联合体实现多态
enum objectType { BALL, TRIANGLE, CYLINDER };
struct Hittable {
	objectType active_type;  // 类型标签
	union {
		Ball ball;
		Triangle triangle;
		Cylinder cylinder;
	};

	__device__ __host__ Hittable() {};

	__device__ __host__ Hittable(const Ball& ball) : active_type(BALL), ball(ball) {}

	__device__ __host__ Hittable(const Triangle& triangle) : active_type(TRIANGLE), triangle(triangle) {}

	__device__ __host__ Hittable(const Cylinder& cylinder) : active_type(CYLINDER), cylinder(cylinder) {}

	// 构造函数和析构函数需手动管理
	__device__ __host__ ~Hittable() {
		if (active_type == BALL) ball.~Ball();
		else if (active_type == TRIANGLE) triangle.~Triangle();
		else if (active_type == CYLINDER) cylinder.~cylinder();
	}

	__device__ __host__ Material* getMaterial() {
		switch (active_type) {
		case BALL:
			return ball.mat_ptr;
		case TRIANGLE:
			return triangle.mat_ptr;
		case CYLINDER:
			return cylinder.mat_ptr;
		}
		return nullptr;
	}

	__device__ __host__ Material** getMaterial_ptr() {
		switch (active_type) {
		case BALL:
			return &ball.mat_ptr;
		case TRIANGLE:
			return &triangle.mat_ptr;
		case CYLINDER:
			return &cylinder.mat_ptr;
		}
		return nullptr;
	}

	// 通过类型标签调用对应的函数
	__device__ bool hit(const Ray& r, interval ray_t, HitRecord& record) const {
		switch (active_type) {
		case BALL:
			return ball.hit(r, ray_t, record);
		case TRIANGLE:
			return triangle.hit(r, ray_t, record);
		case CYLINDER:
			return cylinder.hit(r, ray_t, record);
		}
		return false;
	}

	__host__ Box getBox() {
		switch (active_type) {
		case BALL:
			return ball.getBbox();
		case TRIANGLE:
			return triangle.getBox();
		case CYLINDER:
			return cylinder.getBox();
		}
		//(0, 0, 0) (0, 0, 0)
		return Box(point3(), point3());
	}
};

//简单光照，只在光线迭代层数为 1 时使用
//------------------------------------------------------------------------------------------------//
//                                            Light                                               //
//------------------------------------------------------------------------------------------------//
__device__ __host__ class DotLight {
public:
	point3 position;
	Color emitColor;
	vector3 moveDirection;

	DotLight() {
		position = point3(0, 0, 0);
		emitColor = Color(1, 1, 1);
		moveDirection = vector3(0, 0, 0);
	}
	DotLight(point3 position, Color emitColor) : position(position), emitColor(emitColor) {
		moveDirection = vector3(0, 0, 0);
	}
	DotLight(point3 position, Color emitColor, vector3 moveDirection) : position(position), emitColor(emitColor), moveDirection(moveDirection) {}

	__device__ Color emit(const HitRecord& rec) const {
		return emitColor;
	}

	__device__ point3 getPosition() const {
		return position;
	}
	__device__ vector3 getPositionAt(const double t) const {
		return position + moveDirection * t;
	}
};

//------------------------------------------------------------------------------------------------//
//                                  Bounding Box & HitList                                        //
//------------------------------------------------------------------------------------------------//
__device__ __host__ class BoundingBox {
public:
	Box box;
	int* containObjects;
	int containSize;
	int left;
	int right;

	__device__ bool isLeaf() const { return left == -1 && right == -1;}

	__device__ __host__ BoundingBox() {}
	__host__ BoundingBox(const Box& box, const int containSize = 0) {
		this->box = box;
		containObjects = nullptr;
		this->containSize = containSize;
		left = -1;
		right = -1;
	}
	__host__ BoundingBox(const point3& a, const point3& b, const int containSize = 0) {
		box = Box(
			point3(fmin(a.x(), b.x()), fmin(a.y(), b.y()), fmin(a.z(), b.z())),
			point3(fmax(a.x(), b.x()), fmax(a.y(), b.y()), fmax(a.z(), b.z()))
		);

		containObjects = nullptr;
		this->containSize = containSize;
		left = -1;
		right = -1;
	}

	__host__ ~BoundingBox() {
		if (containObjects != nullptr) {
			cudaFree(containObjects);
		}
		containObjects = nullptr;
	}

	__device__ bool hit(const Ray& r, interval ray_t) const{
		const point3& ray_orig = r.origin();
		const vector3& ray_dir = r.direction();

		for (int axis = 0; axis < 3; axis++) {
			const interval& ax = interval(box.min.e[axis], box.max.e[axis]);
			const double adinv = 1.0 / ray_dir[axis];

			auto t0 = (ax.min - ray_orig[axis]) * adinv;
			auto t1 = (ax.max - ray_orig[axis]) * adinv;

			if (t0 < t1) {
				if (t0 > ray_t.min) ray_t.min = t0;
				if (t1 < ray_t.max) ray_t.max = t1;
			}
			else {
				if (t1 > ray_t.min) ray_t.min = t1;
				if (t0 < ray_t.max) ray_t.max = t0;
			}

			if (ray_t.max <= ray_t.min)
				return false;
		}
		return true;
	}
};

__device__ __host__ class HitList {
public:
	Hittable* objects;
	int listSize;
	BoundingBox* bboxs;
	int bboxSize;
	int* deviceLeafIndices;
	DotLight* lights = nullptr;
	int lightSize = 0;

	//__device__ bool hitWorld(const Ray& r, interval ray_t, HitRecord& record) const {
	//	HitRecord tempRecord;
	//	bool hitAnything = false;
	//	//最近的撞击点，初始化为最大值
	//	double closestSoFar = ray_t.max;

	//	for (int i = 0; i < listSize; i++) {
	//		if (objects[i].hit(r, interval(ray_t.min, closestSoFar), tempRecord)) {
	//			hitAnything = true;
	//			closestSoFar = tempRecord.t;
	//			record = tempRecord;
	//		}
	//	}

	//	return hitAnything;
	//}

	__device__ bool hitWorld(const Ray& r, interval ray_t, HitRecord& record) const {
		// 手动实现栈结构
		const int MAX_STACK_DEPTH = 40; // 足够应对大多数场景(最坏2^40个物体)
		int stack[MAX_STACK_DEPTH];
		int stack_ptr = 0; // 栈顶指针（下一个空闲位置）

		stack[stack_ptr++] = 0; // 压入根节点

		HitRecord tempRecord;
		bool hitAnything = false;
		double closestSoFar = ray_t.max;

		//return false;
		while (stack_ptr > 0) {
			int index = stack[--stack_ptr]; // 弹出栈顶
			//return false;
			if (!bboxs[index].hit(r, ray_t)) continue;
			//return false;
			if (bboxs[index].isLeaf()) { // 叶节点
				//return false;
				for (int i = 0; i < bboxs[index].containSize; i++) {
					if (objects[bboxs[index].containObjects[i]].hit(r, interval(ray_t.min, closestSoFar), tempRecord)) {
					//if (objects[i].hit(r, interval(ray_t.min, closestSoFar), tempRecord)) {
						hitAnything = true;
						closestSoFar = tempRecord.t;
						record = tempRecord;
					}
				}
			}
			else { // 内部节点，按照逆序压入子节点
				stack[stack_ptr++] = bboxs[index].left;
				stack[stack_ptr++] = bboxs[index].right;
			}
		}
		return hitAnything;
	}

	__host__ void createBoundingBoxs() {
		if (listSize <= 0) return;

		// 准备数据
		std::vector<BBoxInfo> bboxInfos;
		for (int i = 0; i < listSize; i++) {
			Box box = objects[i].getBox();
			bboxInfos.push_back({ box, i, (box.min + box.max) * 0.5f });
		}

		// 初始化存储
		BoundingBox* tmpBboxs = (BoundingBox*)malloc(sizeof(BoundingBox) * (2 * listSize - 1));
		int nodeCount = 0;

		//--- 新增: 预分配准备 ---
		std::vector<int> hostLeafIndices;
		std::vector<BoundingBox*> leafNodes;

		// 执行构建（修改后的 createLeafNode 会收集数据）
		buildBVHNode(bboxInfos.data(), 0, listSize, tmpBboxs, nodeCount, hostLeafIndices, leafNodes);

		//--- 预分配设备内存并更新指针 ---
		cudaMalloc(&deviceLeafIndices, hostLeafIndices.size() * sizeof(int));
		cudaMemcpy(deviceLeafIndices, hostLeafIndices.data(),
			hostLeafIndices.size() * sizeof(int), cudaMemcpyHostToDevice);

		for (BoundingBox* node : leafNodes) {
			int hostOffset = (int)(node->containObjects);
			node->containObjects = deviceLeafIndices + hostOffset;
		}

		// 最终存储
		cudaMallocManaged(&bboxs, nodeCount * sizeof(BoundingBox));
		memcpy(bboxs, tmpBboxs, nodeCount * sizeof(BoundingBox));
		bboxSize = nodeCount;
		free(tmpBboxs);
	}
private:
	struct BBoxInfo {
		Box box;
		int original_index;
		point3 center;
	};

	// 递归构建函数
	int buildBVHNode(BBoxInfo* bboxInfos, int start, int end, BoundingBox* bboxs, int& bboxSize, std::vector<int>&hostLeafIndices, std::vector<BoundingBox*>&leafNodes) {
		int current = bboxSize++;

		// 合并当前节点包围盒
		Box box = bboxInfos[start].box;
		for (int i = start + 1; i < end; i++) {
			box += bboxInfos[i].box;
		}
		bboxs[current].box = box;

		// 终止条件处理
		const int count = end - start;
		if (count <= 4) {
			createLeafNode(bboxInfos, start, end, bboxs[current], hostLeafIndices, leafNodes);
			return current;
		}

		// 空间划分逻辑
		const int axis = selectSplitAxis(box);
		sortObjects(bboxInfos, start, end, axis);

		// 递归构建子树
		const int mid = start + count / 2;
		bboxs[current].left = buildBVHNode(bboxInfos, start, mid, bboxs, bboxSize, hostLeafIndices, leafNodes);
		bboxs[current].right = buildBVHNode(bboxInfos, mid, end, bboxs, bboxSize, hostLeafIndices, leafNodes);

		return current;
	}

	void createLeafNode(BBoxInfo* bboxInfos, int start, int end, BoundingBox& node, std::vector<int>& hostLeafIndices, std::vector<BoundingBox*>& leafNodes) {
		// 记录索引到主机端
		int startIdx = hostLeafIndices.size();
		int count = end - start;
		for (int i = 0; i < count; i++) {
			hostLeafIndices.push_back(bboxInfos[start + i].original_index);
		}

		// 临时用指针存储偏移量
		node.containObjects = (int*)startIdx;
		node.containSize = count;
		node.left = -1;
		node.right = -1;

		// 记录需更新的节点
		leafNodes.push_back(&node);
	}

	int selectSplitAxis(const Box& box) const {
		const point3 diag = box.max - box.min;
		return (diag.x() > diag.y() && diag.x() > diag.z()) ? 0 :
			(diag.y() > diag.z()) ? 1 : 2;
	}

	void sortObjects(BBoxInfo* bboxInfos, int start, int end, int axis) {
		int mid = start + (end - start) / 2;
		std::nth_element(bboxInfos + start, bboxInfos + mid, bboxInfos + end,
			[axis](const BBoxInfo& a, const BBoxInfo& b) {
				return a.center.e[axis] < b.center.e[axis];
			});
	}
};

//-----------------------------------------------------------------------------------------------//
//                                           carema                                              //
//-----------------------------------------------------------------------------------------------//

__host__ struct StateofCamera {
	double roll = 0, pitch = 0, yaw = 0;
	vector3 origin = { 0, 0, 0 };
	double angleDegree = 0;
	double focal_length = 2;
	double viewport_width = 4.0;
	double viewport_height = 2.0;
	int nofSubpixel = 3;
	int maxDepth = 30;
	bool showBbox = false; // 是否显示包围盒
	bool light = true;
	Color BGColor_up = Color(0.5, 0.7, 1.0);
	Color BGColor_down = Color(1.0, 1.0, 1.0);
	double time = 0.0;
};

__device__ __host__ class Camera {
public:
	//相机眼点
	point3 origin;
	//视口左下角
	vector3 lower_left_corner;

	//没有采用宽高比例，而是直接设置了视口的宽高
	//视口水平方向（从左到右）
	vector3 horizontal;
	//视口垂直方向（从下到上）
	vector3 vertical;

	double RofLen = 0;
	vector3 viewDirection = vector3(0, 0, -1);

	int nofSubpixel = 1;
	int maxDepth = 2;
	bool showBbox = false; // 是否显示包围盒

	Color BGColor_up = Color(0.5, 0.7, 1.0);
	Color BGColor_down = Color(1.0, 1.0, 1.0);

	double time = 0.0; // 动画时间

	//暂定的相机默认参数
	__device__ __host__ Camera() {
		lower_left_corner = vector3(-2.0, -1.0, -1.0);
		horizontal = vector3(4.0, 0.0, 0.0);
		vertical = vector3(0.0, 2.0, 0.0);
		origin = vector3(0.0, 0.0, 0.0);
	}

	__host__ Camera(StateofCamera& camState) {
		this->origin = camState.origin;
		horizontal = vector3(camState.viewport_width, 0.0, 0.0);
		vertical = vector3(0.0, camState.viewport_height, 0.0);
		viewDirection = vector3(0, 0, -1);
		lower_left_corner = -horizontal / 2 - vertical / 2 - vector3(0.0, 0.0, camState.focal_length);

		_Roll(camState.roll, camState.pitch, camState.yaw);

		lower_left_corner += camState.origin;

		this->nofSubpixel = camState.nofSubpixel;
		this->maxDepth = camState.maxDepth;
		this->RofLen = camState.focal_length * tan(degrees_to_radians(camState.angleDegree) / 2);
		this->showBbox = camState.showBbox;
		this->BGColor_up = camState.BGColor_up;
		this->BGColor_down = camState.BGColor_down;

		this->time = camState.time;
	}

	__host__ Camera(point3 origin, double viewport_width, double viewport_height, double focal_length, int nofSubpixel, int maxDepth, double roll = 0, double pitch = 0, double yaw = 0, double angleDegree = 0) {
		this->origin = origin;
		horizontal = vector3(viewport_width, 0.0, 0.0);
		vertical = vector3(0.0, viewport_height, 0.0);
		viewDirection = vector3(0, 0, -1);
		lower_left_corner = -horizontal / 2 - vertical / 2 - vector3(0.0, 0.0, focal_length);

		_Roll(roll, pitch, yaw);

		lower_left_corner += origin;

		this->nofSubpixel = nofSubpixel;
		this->maxDepth = maxDepth;
		this->RofLen = focal_length * tan(degrees_to_radians(angleDegree) / 2);
	}

	__device__ __host__ double degrees_to_radians(double degrees) {
		return degrees * PI / 180.0;
	}

	__host__ void _Roll(double roll, double pitch, double yaw) {
		lower_left_corner = Roll(lower_left_corner, roll, pitch, yaw);
		horizontal = Roll(horizontal, roll, pitch, yaw);
		vertical = Roll(vertical, roll, pitch, yaw);
		viewDirection = Roll(viewDirection, roll, pitch, yaw);
	}

	__device__  Color BackGroundColor(vector3 direction) {
		double t = 0.5 * (direction.unit_vecttor().y() + 1.0);
		return (1.0 - t) * BGColor_down + t * BGColor_up;
	}

	__device__ Ray get_ray(curandState* local_state, double u, double v) {
		vector3 rayOrigin = origin + RofLen * random_unit_vector_in_disk(local_state, viewDirection);
		return Ray(rayOrigin, lower_left_corner + u * horizontal + v * vertical - rayOrigin);
		//return Ray(point3(0, 0, 0), vector3(-2.0, -1.0, -1.0) + u * vector3(4.0, 0.0, 0.0) + v * vector3(0.0, 2.0, 0.0));
	}

	__device__ Color ray_color(curandState* local_state, const Ray& ray, HitList* world, int maxdepth) {
		int depth = 0;
		Color currentAttenuation(1, 1, 1);
		Color currentEmit(0, 0, 0);
		Ray currentRay = ray;

		if (showBbox) {
			Color bboxColor[3] = { Color(1, 1, 0.95), Color(0.95, 1, 1), Color(1, 0.95, 1) };

			const int MAX_STACK_DEPTH = 40; // 足够应对大多数场景(最坏2^40个物体)
			int stack[MAX_STACK_DEPTH];
			int stack_ptr = 0; // 栈顶指针（下一个空闲位置）

			stack[stack_ptr++] = 0; // 压入根节点

			while (stack_ptr > 0) {
				int index = stack[--stack_ptr]; // 弹出栈顶
				if (!world->bboxs[index].hit(currentRay, interval(0.00000001, Infinity))) continue;

				currentAttenuation *= bboxColor[index % 3];
				if (world->bboxs[index].isLeaf()) { // 叶节点
					continue;
				}
				else { // 内部节点，按照逆序压入子节点
					stack[stack_ptr++] = world->bboxs[index].left;
					stack[stack_ptr++] = world->bboxs[index].right;
				}
			}

			return currentAttenuation;
		}

		while (depth < maxdepth) {
			HitRecord record;

			//对于玻璃，可以将多次折射的光线视为一次折射以获得更好的效果
			int specialCount = 0;

			if (world->hitWorld(currentRay, interval(0.00000001, Infinity), record)) {
				Ray scattered;
				Color attenuation;

				//简单光照
				if (2 == maxDepth) {
					//attenuation = record.mat_ptr->getAlbedo();
					attenuation = record.mat_ptr->getTextureColor(record);
					currentAttenuation *= attenuation;
					//返回简单光照
					for (int i = 0; i < world->lightSize; i++) {
						vector3 lightDir = world->lights[i].getPositionAt(time) - record.hitPoint;
						double lightDistance = lightDir.length();
						lightDir = lightDir.unit_vecttor();

						//判断光线是否被物体遮挡
						Ray lightRay(record.hitPoint, lightDir);
						HitRecord lightRecord;
						if (world->hitWorld(lightRay, interval(0.00000001, lightDistance), lightRecord)) {
							continue;
						}

						//光照衰减
						double lightRate = dot(lightDir, record.normalVector) / (lightDistance * lightDistance);
						if (lightRate < 0) lightRate = 0;
						currentEmit += world->lights[i].emitColor * currentAttenuation * lightRate;

						//镜面反射
						if (record.mat_ptr->active_type == LAMBERTIAN) {
							vector3 reflectedDir = reflect(lightDir, record.normalVector);
							double reflectedRate = dot(reflectedDir.unit_vecttor(), currentRay.direction().unit_vecttor());
							if (reflectedRate < 0) reflectedRate = 0;
							currentEmit += world->lights[i].emitColor * record.mat_ptr->lambertian.fuzzForSimpleLight * pow(reflectedRate, record.mat_ptr->lambertian.nForSimpleLight);
						}
					}
					return currentEmit + currentAttenuation * BackGroundColor(currentRay.direction());
				}

				//光线追踪
				if (record.mat_ptr->scatter(local_state, currentRay, record, attenuation, scattered)) {
					currentRay = scattered;
					//对发光物体的光照进行叠加
					//finalColor = e1 + a1 * e2 + a1 * a2 * e3 + a1 * a2 * a3 * BGColor;
					currentEmit += currentAttenuation * record.mat_ptr->emit(record);
					//吸收率叠乘
					currentAttenuation *= attenuation;
					depth++;
				}
				else {
					//物体没有反射或折射
					return currentEmit + record.mat_ptr->emit(record);
				}
			}
			else {
				//未击中物品，返回背景色与当前光照
				return currentEmit + currentAttenuation * BackGroundColor(currentRay.direction());
			}

			//对一些特殊情况进行处理
			if (1 == maxDepth) {
				//返回物体本色
				return currentAttenuation;
			}


		}



		//递归尽头都击中物品，返回当前光照
		return currentEmit;
	}
};
// 人麻了，CUDA不支持递归
//__device__ __host__ Color ray_color(const Ray& ray, HitList* world, int depth) {
//	if (depth == 1) {
//		return Color(0, 0, 1);
//	}
//	else {
//		return Color(1, 0, 0);
//		return ray_color(ray, world, 1);
//	}
//
//	HitRecord record;
//	
//	if (world->hitWorld(ray, interval(0.00000001, Infinity), record)) {
//		vector3 N = record.normalVector;
//
//		Ray scattered;
//		Color attenuation;
//		
//		if (record.mat_ptr->scatter(ray, record, attenuation, scattered)) {
//			//return Color(1, 0, 0);
//			attenuation = Color(1, 0, 0);
//			scattered = ray;
//			return ray_color(scattered, world, depth + 1);
//		}
//		
//		return 0.5 * Color(N.x() + 1, N.y() + 1, N.z() + 1);
//		//return Color(1, 0, 0);
//	}
//	vector3 unit_direction = unit_vector(ray.direction());
//	//将y映射到[0, 1]
//	double t = 0.5 * (unit_direction.y() + 1.0);
//
//	return Color((1.0 - t) * Color(1.0, 1.0, 1.0) + t * Color(0.5, 0.7, 1.0));
//}

#endif