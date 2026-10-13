#include "rayTracing.cuh"
#include "vector3.cuh"
#include "RayHit.cuh"
#include <curand_kernel.h>
#include <fstream>
#include <sstream>

#include "createVideo.h"

__device__ Color antialiasing(curandState* local_state, double u, double v, double pixelHeight, double pixelWidth, int nofSubpixel, int maxdepth, HitList* world, Camera* cam) {
	Color c(0, 0, 0);
	double subpixelHeight = pixelHeight / nofSubpixel;
	double subpixelWidth = pixelWidth / nofSubpixel;
	for (int i = 0; i < nofSubpixel; i++) {
		for (int j = 0; j < nofSubpixel; j++) {
			double subu = u + subpixelWidth * (i + 0.5);
			double subv = v + subpixelHeight * (j + 0.5);
			c += cam->ray_color(local_state, cam->get_ray(local_state, subu, subv), world, maxdepth);
		}
	}
	return c / (nofSubpixel * nofSubpixel);
}

__global__ void rayTracingKernel(curandState* states, uchar4* ptr, int width, int height, HitList* world, Camera* cam) {
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
	if (x >= width || y >= height) return;

	int index = y * width + x;
	curandState local_state = states[index];

	double u = (double)x / width;
	double v = (double)y / height;
	//ptr[index] = ray_color(get_ray(u, v)).toRGB();
	ptr[index] = antialiasing(&local_state, u, v, 1.0 / width, 1.0 / height, cam->nofSubpixel, cam->maxDepth, world, cam).toRGB();
}

__global__ void innitRandomState(curandState* states, int width, int height) {
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
	if (x >= width || y >= height) return;

	int index = y * width + x;
	curand_init(1234, index, 0, states + index);
}

__host__ void test(uchar4* ptr, int width, int height) {
	for (int y = 0; y < height/2; y++) {
		for (int x = 0; x < width/2; x++) {
			int index = y * width + x;
			ptr[index] = Color(vector3((double)x / width, (double)y / height, 1)).toRGB();
		}
	}
}


HitList* deviceWorld = nullptr;
curandState* deviceStates = nullptr;
Camera* deviceCamera = nullptr;
uchar4* deviceBitmap = nullptr;
uchar4* hostBitmap = nullptr;

__host__ void rander(HWND hWnd, HDC hdc, Camera& cam, bool saveBMP, bool resized, int typeofworld) {
	RECT clientRect;
	GetClientRect(hWnd, &clientRect);
	int width = clientRect.right - clientRect.left;
	int height = clientRect.bottom - clientRect.top;

	cudaError_t err;

	if (hostBitmap == nullptr) {
		hostBitmap = (uchar4*)malloc(width * height * sizeof(uchar4));
		memset(hostBitmap, 0, width * height * sizeof(uchar4));
	}
	else if (resized) {
		free(hostBitmap);
		hostBitmap = (uchar4*)malloc(width * height * sizeof(uchar4));
		memset(hostBitmap, 0, width * height * sizeof(uchar4));
	}

	if (deviceBitmap == nullptr) {
		err = cudaMallocManaged(&deviceBitmap, width * height * sizeof(uchar4));
		if (err != cudaSuccess) {
			// 处理错误
			return;
		}
		cudaMemcpy(deviceBitmap, hostBitmap, width * height * sizeof(uchar4), cudaMemcpyHostToDevice);
	}
	else if (resized) {
		cudaFree(deviceBitmap);
		err = cudaMallocManaged(&deviceBitmap, width * height * sizeof(uchar4));
		if (err != cudaSuccess) {
			// 处理错误
			return;
		}
		cudaMemcpy(deviceBitmap, hostBitmap, width * height * sizeof(uchar4), cudaMemcpyHostToDevice);
	}

	if (deviceWorld == nullptr) {
		FILE* fp = fopen("log.txt", "a");
		if (fp == nullptr) {
			fprintf(stderr, "Failed to open log.txt\n");
			return;
		}
		fprintf(fp, "Creating world...\n");
		double startTime = clock();
		HitList* deviceWorld = createWorld(cam, typeofworld);
		double endTime = clock();
		fprintf(fp, "World created in %f seconds\n", (endTime - startTime) / CLOCKS_PER_SEC);
		fprintf(fp, "World size: %d\n", deviceWorld->listSize);
		fprintf(fp, "World BVH size: %d\n", deviceWorld->bboxSize);
		fclose(fp);
	}

	dim3 blockSize(16, 16);
	dim3 numBlocks((width + blockSize.x - 1) / blockSize.x, (height + blockSize.y - 1) / blockSize.y);

	int total_threads = width * height;

	if (saveBMP) {
		goto CPYBITMAP;
	}

	if (deviceCamera == nullptr)
		cudaMalloc(&deviceCamera, sizeof(Camera));

	cudaMemcpy(deviceCamera, &cam, sizeof(Camera), cudaMemcpyHostToDevice);

	if (deviceStates == nullptr) {
		cudaMalloc(&deviceStates, total_threads * sizeof(curandState));
	}
	else if (resized) {
		cudaFree(deviceStates);
		cudaMalloc(&deviceStates, total_threads * sizeof(curandState));
	}

	innitRandomState << <numBlocks, blockSize >> > (deviceStates, width, height);
	rayTracingKernel << <numBlocks, blockSize >> > (deviceStates, deviceBitmap, width, height, deviceWorld, deviceCamera);

	// 检查内核执行错误
	err = cudaGetLastError();
	if (err != cudaSuccess) {
		// 处理错误
		cudaFree(deviceBitmap);
		exit(4);
	}

	cudaDeviceSynchronize();

	cudaMemcpy(hostBitmap, deviceBitmap, width * height * sizeof(uchar4), cudaMemcpyDeviceToHost);

CPYBITMAP:
	//test(hostBitmap, width, height);
	BITMAPINFO bmpInfo;

	bmpInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
	bmpInfo.bmiHeader.biWidth = width;
	bmpInfo.bmiHeader.biHeight = height;
	bmpInfo.bmiHeader.biPlanes = 1;
	bmpInfo.bmiHeader.biBitCount = 32;
	bmpInfo.bmiHeader.biCompression = BI_RGB;
	bmpInfo.bmiHeader.biSizeImage = 0;
	bmpInfo.bmiHeader.biXPelsPerMeter = 0;
	bmpInfo.bmiHeader.biYPelsPerMeter = 0;
	bmpInfo.bmiHeader.biClrUsed = 0;
	bmpInfo.bmiHeader.biClrImportant = 0;

	SetDIBitsToDevice(hdc, 0, 0, width, height, 0, 0, 0, height, hostBitmap, &bmpInfo, DIB_RGB_COLORS);
}

//-------------------------------------------------------------------------------------------------//
//                                        create world                                             //
//-------------------------------------------------------------------------------------------------//

#include <unordered_map>
#include <mutex>
#include <memory>

// 自定义删除器，用于释放 CUDA 内存
struct ImageTextureDataDeleter {
	void operator()(ImageTexture* textureData) {
		if (textureData) {
			if (textureData->data) {
				cudaFree(textureData->data);  // 释放贴图数据内存
			}
			cudaFree(textureData);  // 释放 ImageTexture 对象本身
		}
	}
};

using ImageTextureDataPtr = std::shared_ptr<ImageTexture>;  // 智能指针类型

// 全局贴图缓存（线程安全）
static std::unordered_map<std::string, ImageTextureDataPtr> imageTextureDataCache;
static std::mutex cacheMutex;

__host__ Texture* createBoardTexture(const Color color, const double scale, Texture* oddTexture, Texture* evenTexture) {
	Texture* deviceTexture;
	cudaError_t cudaStatus = cudaMallocManaged(&deviceTexture, sizeof(Texture));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "Failed to allocate ImageTexture: %s\n", cudaGetErrorString(cudaStatus));
		return deviceTexture;
	}
	deviceTexture->active_type = BOARD;
	deviceTexture->albedo = color;
	deviceTexture->board.scale = scale;
	deviceTexture->board.oddTexture = oddTexture;
	deviceTexture->board.evenTexture = evenTexture;

	return deviceTexture;
}

__host__ Texture* createTexture(textureType texType, Color color, const char* filename = nullptr, double scale = 1, int depth = 0, Perlin* device_perlin = nullptr) {
	Texture* deviceTexture;
	cudaError_t cudaStatus = cudaMallocManaged(&deviceTexture, sizeof(Texture));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "Failed to allocate ImageTexture: %s\n", cudaGetErrorString(cudaStatus));
		return deviceTexture;
	}
	deviceTexture->active_type = texType;
	deviceTexture->albedo = color;
	switch (deviceTexture->active_type)	{
		case SOLID:
			break;
		case NOISE: {
			deviceTexture->noise.scale = scale;
			deviceTexture->noise.depth = depth;
			if (device_perlin == nullptr) {
				Perlin host_perlin;
				cudaStatus = cudaMallocManaged(&deviceTexture->noise.perlin, sizeof(Perlin));
				if (cudaStatus != cudaSuccess) {
					fprintf(stderr, "Failed to allocate Perlin: %s\n", cudaGetErrorString(cudaStatus));
					deviceTexture->active_type = SOLID;
					break;
				}
				cudaStatus = cudaMemcpy(deviceTexture->noise.perlin, &host_perlin, sizeof(Perlin), cudaMemcpyHostToDevice);
				if (cudaStatus != cudaSuccess) {
					fprintf(stderr, "Failed to copy Perlin: %s\n", cudaGetErrorString(cudaStatus));
					deviceTexture->active_type = SOLID;
					break;
				}
			}
			else {
				deviceTexture->noise.perlin = device_perlin;
			}
		}
		break;
		case IMAGE: {
			if (filename != nullptr) {
				std::lock_guard<std::mutex> lock(cacheMutex);  // 加锁保证线程安全

				// 检查贴图是否已缓存
				auto& cachedTexture = imageTextureDataCache[filename];
				if (!cachedTexture) {
					// 未缓存，加载贴图
					std::fstream fin(filename, std::ios::in | std::ios::binary);
					if (!fin) {
						fprintf(stderr, "Failed to open file: %s\n", filename);
						deviceTexture->active_type = SOLID;
						break;
					}

					BMPFileHeader fileHeader;
					BMPInfoHeader infoHeader;
					fin.read(reinterpret_cast<char*>(&fileHeader), sizeof(BMPFileHeader));
					fin.read(reinterpret_cast<char*>(&infoHeader), sizeof(BMPInfoHeader));

					if (infoHeader.biBitCount != 32) {
						fprintf(stderr, "Unsupported BMP format: %d bits/pixel\n", infoHeader.biBitCount);
						deviceTexture->active_type = SOLID;
						fin.close();
						break;
					}

					const int height = infoHeader.biHeight;
					const int width = infoHeader.biWidth;
					const size_t dataSize = abs(height) * width * 4 * sizeof(unsigned char);

					//小于0有特殊处理
					//创建一个临时的 ImageTexture 对象，用于存储数据并与 Material 中的指针分离
					ImageTexture* imageData;
					cudaStatus = cudaMallocManaged(&imageData, sizeof(ImageTexture));
					if (cudaStatus != cudaSuccess) {
						fprintf(stderr, "Failed to allocate ImageTexture: %s\n", cudaGetErrorString(cudaStatus));
						deviceTexture->active_type = SOLID;
						fin.close();
						break;
					}

					imageData->height = height;
					imageData->width = width;

					cudaStatus = cudaMallocManaged(&imageData->data, dataSize);
					if (cudaStatus != cudaSuccess) {
						fprintf(stderr, "Failed to allocate texture data: %s\n", cudaGetErrorString(cudaStatus));
						deviceTexture->active_type = SOLID;
						fin.close();
						break;
					}

					// 读取数据到临时缓冲区
					std::vector<unsigned char> tempData(dataSize);
					fin.read(reinterpret_cast<char*>(tempData.data()), dataSize);

					// 数据拷贝到 CUDA 内存
					cudaMemcpy(imageData->data, tempData.data(), dataSize, cudaMemcpyHostToDevice);
					fin.close();

					// 将贴图存入缓存
					cachedTexture.reset(imageData, ImageTextureDataDeleter());

					// 将贴图数据指针赋值给原始纹理
					deviceTexture->image.data = imageData->data;
					deviceTexture->image.height = imageData->height;
					deviceTexture->image.width = imageData->width;
				}
				else {
					// 已缓存，直接使用
					deviceTexture->image.data = cachedTexture.get()->data;
					deviceTexture->image.height = cachedTexture.get()->height;
					deviceTexture->image.width = cachedTexture.get()->width;
				}
			}
		}
		break;
	}
	return deviceTexture;
}

__host__ Material* createMaterial(materialType matType, Texture* deviceTexture, double f = 0, Color emitColor = Color(0, 0, 0), double nForSimpleLight = 2) {
	Material* deviceMaterial;
	cudaError_t cudaStatus = cudaMallocManaged(&deviceMaterial, sizeof(Material));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "Failed to allocate Material: %s\n", cudaGetErrorString(cudaStatus));
		return nullptr;
	}
	deviceMaterial->active_type = matType;

	switch (deviceMaterial->active_type) {
	case materialType::LAMBERTIAN:
		deviceMaterial->lambertian.texture_ptr = deviceTexture;
		deviceMaterial->lambertian.fuzzForSimpleLight = f;
		deviceMaterial->lambertian.emitColor = emitColor;
		deviceMaterial->lambertian.nForSimpleLight = nForSimpleLight;
		break;
	case materialType::METAL:
		deviceMaterial->metal.texture_ptr = deviceTexture;
		deviceMaterial->metal.fuzz = f;
		deviceMaterial->metal.emitColor = emitColor;
		break;
	case materialType::GLASS:
		deviceMaterial->glass.texture_ptr = deviceTexture;
		deviceMaterial->glass.ref_idx = f;
		deviceMaterial->glass.emitColor = emitColor;
		break;
	}

	return deviceMaterial;
}

__host__ int addObject(Hittable object, int& count) {
	if (count >= deviceWorld->listSize) {
		//count++;
		return -1;
	}

	cudaMemcpy(deviceWorld->objects + count, &object, sizeof(Hittable), cudaMemcpyHostToDevice);
	count++;
	return 1;
}

__host__ void setObject(Hittable object, int index) {
	if (index >= deviceWorld->listSize) {
		return;
	}
	cudaMemcpy(deviceWorld->objects + index, &object, sizeof(Hittable), cudaMemcpyHostToDevice);
}

struct surface {
	point3 p1;
	point3 p2;
	point3 p3;
	vector3 vn1;
	vector3 vn2;
	vector3 vn3;
	vector3 u;
	vector3 v;
};

__host__ void readObj(const char* filename, std::vector<surface>& surfaces, vector3 position = vector3(0, 0, 0), double scale = 1, vector3 roll = vector3(0, 0, 0)) {
	std::fstream fin(filename, std::ios::in);
	if (!fin.is_open()) {
		fprintf(stderr, "Failed to open file: %s\n", filename);
		exit(1);
	}

	std::string line;

	std::vector<point3> points;
	std::vector<vector3> normals;
	std::vector<double> us;
	std::vector<double> vs;

	point3 p;
	vector3 n;
	surface s;
	double u, v;
	int p1, p2, p3, n1 = -1, n2 = -1, n3 = -1, v1 = -1, v2 = -1, v3 = -1;
	while (std::getline(fin, line)) {
		if (line.find("v ") == 0) {
			// 解析顶点数据
			sscanf_s(line.c_str(), "v %lf %lf %lf", &p.e[0], &p.e[1], &p.e[2]);
			p = Roll(p, roll.x(), roll.y(), roll.z());
			points.push_back(p);
		}

		else if (line.find("vt ") == 0) {
			// 解析纹理坐标数据
			sscanf_s(line.c_str(), "vt %lf %lf", &u, &v);
			us.push_back(u);
			vs.push_back(v);
		}
		else if (line.find("vn ") == 0) {
			// 解析法线数据
			sscanf_s(line.c_str(), "vn %lf %lf %lf", &n.e[0], &n.e[1], &n.e[2]);
			n = Roll(n, roll.x(), roll.y(), roll.z());
			normals.push_back(n);
		}
		else if (line.find("f ") == 0) {
			// 解析顶点数据
			// 暂定的兼容不同格式的解析方法
			if (sscanf_s(line.c_str(), "f %d//%d %d//%d %d//%d", &p1, &n1, &p2, &n2, &p3, &n3) != 6) {
				if (sscanf_s(line.c_str(), "f %d %d %d", &p1, &p2, &p3) != 3) {
					if (sscanf_s(line.c_str(), "f %d/%d/%d %d/%d/%d %d/%d/%d", &p1, &v1, &n1, &p2, &v2, &n2, &p3, &v3, &n3) != 9) {
						if (sscanf_s(line.c_str(), "f %d/%d %d/%d %d/%d", &p1, &v1, &p2, &v2, &p3, &v3) != 6) {
							exit(-1);
						}
					}
					//// 解析纹理坐标数据
					//s.u = vector3(us[v1 - 1], us[v2 - 1], us[v3 - 1]);
					//s.v = vector3(vs[v1 - 1], vs[v2 - 1], vs[v3 - 1]);
				}
				//else {
				//	// 解析纹理坐标数据
				//	s.u = vector3(0, 0, 0);
				//	s.v = vector3(0, 0, 0);
				//}
			}
			//else {
			//	// 解析纹理坐标数据
			//	s.u = vector3(0, 1, 0);
			//	s.v = vector3(0, 0, 1);
			//}
			s.p1 = scale * points[p1 - 1] + position; // obj文件的索引从1开始
			s.p2 = scale * points[p2 - 1] + position;
			s.p3 = scale * points[p3 - 1] + position;

			if (v1 != -1 && v2 != -1 && v3 != -1) {
				s.u = vector3(us[v1 - 1], us[v2 - 1], us[v3 - 1]);
				s.v = vector3(vs[v1 - 1], vs[v2 - 1], vs[v3 - 1]);
			}
			else {
				s.u = vector3(0, 1, 0);
				s.v = vector3(0, 0, 1);
			}

			// 解析法线数据
			if (n1 != -1 && n2 != -1 && n3 != -1) {
				s.vn1 = normals[n1 - 1];
				s.vn2 = normals[n2 - 1];
				s.vn3 = normals[n3 - 1];
			}
			else {
				s.vn1 = vector3(0, 0, 0);
				s.vn2 = vector3(0, 0, 0);
				s.vn3 = vector3(0, 0, 0);
			}
			n1 = n2 = n3 = -1; //重置法线索引
			//记录面在vector中的位置
			surfaces.push_back(s);
		}
	}
	fin.close();
}

__host__ int addObjSurfaces(const std::vector<surface>& surfaces, Material** deviceMat, const int& nofMaterial, int& count) {
	if (count + surfaces.size() > deviceWorld->listSize) {
		return -1;
	}

	std::vector<Hittable> host_objects;
	for (int i = 0; i < surfaces.size(); i++) {
		host_objects.emplace_back(
			Hittable(
				Triangle(
					surfaces[i].p1, surfaces[i].p2, surfaces[i].p3,
					deviceMat[i % nofMaterial],
					surfaces[i].u, surfaces[i].v
				)
			)
		);		
	}
	cudaMemcpy(deviceWorld->objects + count, host_objects.data(), sizeof(Hittable) * host_objects.size(), cudaMemcpyHostToDevice);
	count += host_objects.size();

	return 1;
}

__host__ int addBezierSurfaces(const std::vector<std::vector<point3>>& points, Material** deviceMat, const int& nofMaterial, int& count) {
	const int width = points.front().size();
	const int height = points.size();
	point3* controlPoints = (point3*)malloc(sizeof(point3) * width * height);
	//point3 controlPoints[16];
	for (int i = 0; i < height; i++) {
		for (int j = 0; j < width; j++) {
			controlPoints[i * width + j] = points[i][j];
		}
	}
	point3* tempPoints = (point3*)malloc(sizeof(point3) * width * height);
	//point3 tempPoints[16];
	point3 bezierPoints[101][101];

	for (int u = 0; u <= 100; u++) {
		for (int v = 0; v <= 100; v++) {
			double u1 = (double)u / 100;
			double v1 = (double)v / 100;
			for (int i = 0; i < height; i++) {
				for (int j = 0; j < width; j++) {
					tempPoints[i * width + j] = controlPoints[i * width + j];
				}
			}
			int heightIndex = height;
			while (heightIndex != 1) {
				for (int i = 0; i < heightIndex - 1; i++) {
					for (int j = 0; j < width; j++) {
						tempPoints[i * width + j] = (1 - u1) * tempPoints[i * width + j] + u1 * tempPoints[(i + 1) * width + j];
					}
				}
				heightIndex--;
			}
			int widthIndex = width;
			while (widthIndex != 1) {
				for (int j = 0; j < widthIndex - 1; j++) {
					tempPoints[j] = (1 - v1) * tempPoints[j] + v1 * tempPoints[j + 1];
				}
				widthIndex--;
			}
			bezierPoints[u][v] = tempPoints[0];
		}
	}
	std::vector<Hittable> host_objects;
	for (int u = 0; u < 100; u++) {
		for (int v = 0; v < 100; v++) {
			host_objects.emplace_back(
				Hittable(
					Triangle(
						bezierPoints[u][v], bezierPoints[u + 1][v], bezierPoints[u][v + 1],
						deviceMat[(u * 100 + v) % nofMaterial],
						0.01 * vector3(u, u + 1, u), 0.01 * vector3(v, v, v + 1)
					)
				)
			);
			host_objects.emplace_back(
				Hittable(
					Triangle(
						bezierPoints[u + 1][v], bezierPoints[u + 1][v + 1], bezierPoints[u][v + 1],
						deviceMat[(u * 100 + v) % nofMaterial],
						0.01 * vector3(u + 1, u + 1, u), 0.01 * vector3(v, v + 1, v + 1)
					)
				)
			);
		}
	}

	free(controlPoints);
	free(tempPoints);

	if (count + host_objects.size() > deviceWorld->listSize) {
		return -1;
	}

	cudaMemcpy(deviceWorld->objects + count, host_objects.data(), sizeof(Hittable) * host_objects.size(), cudaMemcpyHostToDevice);
	count += host_objects.size();

	return 1;
}

// 计算三次均匀B样条基函数
__host__ __device__ void calculateBasis(double u, double& N0, double& N1, double& N2, double& N3) {
	double u2 = u * u;
	double u3 = u2 * u;

	N0 = (1.0 - 3 * u + 3 * u2 - u3) / 6.0;
	N1 = (4.0 - 6 * u2 + 3 * u3) / 6.0;
	N2 = (1.0 + 3 * u + 3 * u2 - 3 * u3) / 6.0;
	N3 = u3 / 6.0;
}

__host__ int addBSplineSurfaces(const std::vector<std::vector<point3>>& points,	Material** deviceMat, const int& nofMaterial, int& count) {
	const int width = points.front().size();
	const int height = points.size();

	// 需要至少4×4的控制点网格
	if (width < 4 || height < 4) return -1;

	const int uSegments = width - 3;   // u方向曲面片数量
	const int vSegments = height - 3;  // v方向曲面片数量
	const int resolution = 100;        // 每个曲面片采样分辨率

	std::vector<Hittable> host_objects;

	// 遍历所有曲面片
	for (int uSeg = 0; uSeg < uSegments; ++uSeg) {
		for (int vSeg = 0; vSeg < vSegments; ++vSeg) {

			// 存储当前曲面片的采样点
			point3* surfacePoints = (point3*)malloc((resolution + 1) * (resolution + 1) * sizeof(point3));

			// 生成曲面采样点
			for (int su = 0; su <= resolution; ++su) {
				double u = su / (double)resolution;
				double Nu[4];
				calculateBasis(u, Nu[0], Nu[1], Nu[2], Nu[3]);

				for (int sv = 0; sv <= resolution; ++sv) {
					double v = sv / (double)resolution;
					double Nv[4];
					calculateBasis(v, Nv[0], Nv[1], Nv[2], Nv[3]);

					// 加权求和计算曲面点
					point3 p(0, 0, 0);
					for (int i = 0; i < 4; ++i) {    // v方向控制点索引
						for (int j = 0; j < 4; ++j) { // u方向控制点索引
							const point3& cp = points[vSeg + i][uSeg + j];
							p += Nu[j] * Nv[i] * cp; // 基函数乘积加权
						}
					}
					surfacePoints[su * (resolution + 1) + sv] = p;
				}
			}

			// 生成三角形网格
			for (int su = 0; su < resolution; ++su) {
				for (int sv = 0; sv < resolution; ++sv) {
					// 获取四个顶点
					point3& p00 = surfacePoints[su * (resolution + 1) + sv];
					point3& p10 = surfacePoints[(su + 1) * (resolution + 1) + sv];
					point3& p01 = surfacePoints[su * (resolution + 1) + sv + 1];
					point3& p11 = surfacePoints[(su + 1) * (resolution + 1) + sv + 1];

					// 添加两个三角形
					host_objects.emplace_back(
						Hittable(Triangle(p00, p10, p01,
							deviceMat[(uSeg * vSegments + vSeg) % nofMaterial],
							0.01 * vector3(su, su + 1, su),
							0.01 * vector3(sv, sv, sv + 1)))
					);

					host_objects.emplace_back(
						Hittable(Triangle(p10, p11, p01,
							deviceMat[(uSeg * vSegments + vSeg) % nofMaterial],
							0.01 * vector3(su + 1, su + 1, su),
							0.01 * vector3(sv, sv + 1, sv + 1)))
					);
				}
			}

			free(surfacePoints); // 释放当前曲面片内存
		}
	}

	// 检查设备内存并拷贝数据
	if (count + host_objects.size() > deviceWorld->listSize) {
		return -1;
	}

	cudaMemcpy(deviceWorld->objects + count, host_objects.data(),
		sizeof(Hittable) * host_objects.size(), cudaMemcpyHostToDevice);
	count += host_objects.size();

	return 1;
}

__host__ HitList* createWorld(Camera& cam, int typeofworld = 0) {
	cudaMallocManaged(&deviceWorld, sizeof(HitList));
	int count = 0;

	switch (typeofworld) {
	case 0: {
		std::vector<surface> surfaces_steve;
		readObj("obj\\minecraft\\steve.obj", surfaces_steve, vector3(0, 9, 0), 1, vector3(-PI / 2, 2.1, 0));
		std::vector<surface> surfaces_zombie;
		readObj("obj\\minecraft\\zombie.obj", surfaces_zombie, vector3(0, 9, 0), 1, vector3(-PI / 2, 2.1, 0));
		std::vector<surface> surfaces_skeleton;
		readObj("obj\\minecraft\\skeleton.obj", surfaces_skeleton, vector3(0, 9, 0), 1, vector3(-PI / 2, 2.1, 0));
		std::vector<surface> surfaces_creeper;
		readObj("obj\\minecraft\\creeper.obj", surfaces_creeper, vector3(0, 9, 0), 1, vector3(-PI / 2, 2.1, 0));
		std::vector<surface> surfaces_enderman;
		readObj("obj\\minecraft\\enderman.obj", surfaces_enderman, vector3(0, 5, 0), 5);

		int nofSurfaces = surfaces_steve.size() + surfaces_zombie.size() + surfaces_skeleton.size() + surfaces_creeper.size() + surfaces_enderman.size();

		deviceWorld->listSize = nofSurfaces + 1; //+1 for ground
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable) * deviceWorld->listSize);

		Texture* deviceTex_ground_odd = createTexture(textureType::SOLID, Color(0.7, 0.5, 0.3));
		Texture* deviceTex_ground_even = createTexture(textureType::SOLID, Color(0.5, 0.5, 0.5));
		Texture* deviceTex_ground = createBoardTexture(Color(0.5, 0.5, 0.5), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Material* deviceMat_ground = createMaterial(materialType::LAMBERTIAN, deviceTex_ground);
		addObject(Hittable(Ball(point3(0, -1000, 0), 1000, deviceMat_ground)), count);

		Texture* deviceTex_steve = createTexture(textureType::IMAGE, Color(0.5, 0.5, 0.5), "ImageTexture\\minecraft\\steve.bmp");
		Material* deviceMat_steve = createMaterial(materialType::LAMBERTIAN, deviceTex_steve, 0, Color(0.5, 0.5, 0.5));
		addObjSurfaces(surfaces_steve, &deviceMat_steve, 1, count);

		Texture* deviceTex_zombie = createTexture(textureType::IMAGE, Color(0.5, 0.5, 0.5), "ImageTexture\\minecraft\\zombie.bmp");
		Material* deviceMat_zombie = createMaterial(materialType::LAMBERTIAN, deviceTex_zombie, 0, Color(0.5, 0.5, 0.5));
		addObjSurfaces(surfaces_zombie, &deviceMat_zombie, 1, count);

		Texture* deviceTex_skeleton = createTexture(textureType::IMAGE, Color(0.5, 0.5, 0.5), "ImageTexture\\minecraft\\skeleton.bmp");
		Material* deviceMat_skeleton = createMaterial(materialType::LAMBERTIAN, deviceTex_skeleton, 0, Color(0.5, 0.5, 0.5));
		addObjSurfaces(surfaces_skeleton, &deviceMat_skeleton, 1, count);

		Texture* deviceTex_creeper = createTexture(textureType::IMAGE, Color(0.5, 0.5, 0.5), "ImageTexture\\minecraft\\creeper.bmp");
		Material* deviceMat_creeper = createMaterial(materialType::LAMBERTIAN, deviceTex_creeper, 0, Color(0.5, 0.5, 0.5));
		addObjSurfaces(surfaces_creeper, &deviceMat_creeper, 1, count);

		Texture* deviceTex_enderman = createTexture(textureType::IMAGE, Color(0.5, 0.5, 0.5), "ImageTexture\\minecraft\\enderman.bmp");
		Material* deviceMat_enderman = createMaterial(materialType::GLASS, deviceTex_enderman, 1, Color(0.5, 0.5, 0.5));
		addObjSurfaces(surfaces_enderman, &deviceMat_enderman, 1, count);
	}
	break;
	case 1: {
		std::vector<surface> surfaces_buddha;
		readObj("obj\\buddha.obj", surfaces_buddha, vector3(0, -1, 2), 20, vector3(PI / 2, 2.1, 0));
		std::vector<surface> surfaces_hand;
		readObj("obj\\hand.obj", surfaces_hand);
		std::vector<surface> surfaces_armadillo;
		readObj("obj\\bunny2k_f.obj", surfaces_armadillo, vector3(-2, 1, 0));
		readObj("obj\\armadillo.obj", surfaces_armadillo, vector3(4, 3, 2), 5, vector3(0, 2.1, 0));
		std::vector<surface> surfaces_sphere;
		readObj("obj\\sphere.obj", surfaces_sphere, vector3(-2, 3, 0));
		std::vector<surface> surfaces_kunkun;
		readObj("obj\\kunkun.obj", surfaces_kunkun, vector3(6, 1, 1.5), 1, vector3(0, 2.1, 0));

		deviceWorld->listSize = surfaces_hand.size() + surfaces_buddha.size() + surfaces_armadillo.size() + surfaces_sphere.size() + surfaces_kunkun.size() + 1 + 2; //+1 for ground
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable) * deviceWorld->listSize);

		Texture* deviceTex_ground_odd = createTexture(textureType::SOLID, Color(0.7, 0.5, 0.3));
		Texture* deviceTex_ground_even = createTexture(textureType::SOLID, Color(0.5, 0.5, 0.5));
		Texture* deviceTex_ground = createBoardTexture(Color(0.5, 0.5, 0.5), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Material* deviceMat_ground = createMaterial(materialType::LAMBERTIAN, deviceTex_ground);
		addObject(Hittable(Ball(point3(0, -1000, 0), 1000, deviceMat_ground)), count);

		Texture* deviceTex_buddha = createTexture(textureType::NOISE, Color(0.45, 0.35, 0.1), nullptr, 0.5, 7);
		Material* deviceMat_buddha = createMaterial(materialType::LAMBERTIAN, deviceTex_buddha, 0, Color(0.45, 0.35, 0.1));
		addObjSurfaces(surfaces_buddha, &deviceMat_buddha, 1, count);

		Texture* deviceTex_hand = createTexture(textureType::SOLID, Color(0.9, 0.2, 0.2));
		Material* deviceMat_hand = createMaterial(materialType::METAL, deviceTex_hand, 0.01);
		addObjSurfaces(surfaces_hand, &deviceMat_hand, 1, count);

		Texture* deviceTex_random[100];
		for (int i = 0; i < 100; i++) {
			deviceTex_random[i] = createTexture(textureType::SOLID, Color::random());
		}
		Material* deviceMat_random[100];
		for (int i = 0; i < 100; i++) {
			deviceMat_random[i] = createMaterial(materialType::LAMBERTIAN, deviceTex_random[i]);
		}
		addObjSurfaces(surfaces_armadillo, deviceMat_random, 100, count);

		Texture* deviceTex_sphere = createTexture(textureType::IMAGE, Color(0.5, 0.5, 0.5), "ImageTexture\\earthmap.bmp");
		Material* deviceMat_sphere_emit = createMaterial(materialType::LAMBERTIAN, deviceTex_sphere, 0, Color(1.0, 1.0, 1.0));
		addObjSurfaces(surfaces_sphere, &deviceMat_sphere_emit, 1, count);

		Texture* deviceTex_kunkun = createTexture(textureType::IMAGE, Color(0.5, 0.5, 0.5), "ImageTexture\\kunkun.bmp");
		Material* deviceMat_kunkun = createMaterial(materialType::METAL, deviceTex_kunkun, 0.01, Color(2.0, 2.0, 2.0));
		addObjSurfaces(surfaces_kunkun, &deviceMat_kunkun, 1, count);

		Texture* deviceTex_glass = createTexture(textureType::SOLID, Color(1, 1, 1));
		Material* deviceMat_glass = createMaterial(materialType::GLASS, deviceTex_glass, 1.5);
		addObject(Hittable(Ball(point3(2.6, 2.5, -2.6), 1.0, deviceMat_glass)), count);

		Texture* deviceTex_bubble = createTexture(textureType::IMAGE, Color(1, 1, 1), "ImageTexture\\head3.bmp");
		//Texture* deviceTex_bubble = createTexture(textureType::NOISE, Color(1, 1, 1), nullptr, 1, 7);
		Material* deviceMat_bubble = createMaterial(materialType::GLASS, deviceTex_bubble, 1.0 / 1.5, Color(0.9, 0.2, 0.2));
		addObject(Hittable(Ball(point3(2.6, 2.5, -2.6), -0.8, deviceMat_bubble)), count);
	}
	break;
	case 2: {
		deviceWorld->listSize = 6;
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable) * deviceWorld->listSize);

		//Texture* deviceTex_ground_odd = createTexture(textureType::SOLID, Color(0.7, 0.5, 0.3));
		//Texture* deviceTex_ground_even = createTexture(textureType::SOLID, Color(0.5, 0.5, 0.5));
		//Texture* deviceTex_ground = createBoardTexture(Color(0.5, 0.5, 0.5), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Texture* deviceTex_ground_odd = createTexture(textureType::NOISE, Color(1, 0, 0), nullptr, 1, 7);
		Texture* deviceTex_ground_even = createTexture(textureType::NOISE, Color(0, 1, 0), nullptr, 1, 7, deviceTex_ground_odd->noise.perlin);
		Texture* deviceTex_ground = createBoardTexture(Color(1, 1, 1), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Texture* deviceTex_center = createTexture(textureType::IMAGE, Color(0.0, 1.0, 0.0), "ImageTexture\\dog.bmp");
		Texture* deviceTex_left = createTexture(textureType::SOLID, Color(1.0, 1.0, 1.0));
		Texture* deviceTex_bubble = createTexture(textureType::SOLID, Color(1.0, 1.0, 1.0));
		Texture* deviceTex_right = createTexture(textureType::IMAGE, Color(0.8, 0.6, 0.2), "ImageTexture\\earthmap.bmp");
		Texture* deviceTex_screen = createTexture(textureType::IMAGE, Color(0.9, 0.9, 0.9), "ImageTexture\\earthmap.bmp");

		Material* deviceMat_ground = createMaterial(materialType::LAMBERTIAN, deviceTex_ground);
		Material* deviceMat_center = createMaterial(materialType::LAMBERTIAN, deviceTex_center);
		Material* deviceMat_left = createMaterial(materialType::GLASS, deviceTex_left, 1.5);
		Material* deviceMat_bubble = createMaterial(materialType::GLASS, deviceTex_bubble, 1.0 / 1.5);
		Material* deviceMat_right = createMaterial(materialType::METAL, deviceTex_right, 0.05);
		Material* deviceMat_screen = createMaterial(materialType::METAL, deviceTex_screen, 0.001);

		addObject(Hittable(Ball(point3(0, 0, -1.2), 0.5, deviceMat_center)), count);
		addObject(Hittable(Ball(point3(0, -10000.5, -1), 10000, deviceMat_ground)), count);
		addObject(Hittable(Ball(point3(-1, 0, -1), 0.5, deviceMat_left)), count);
		addObject(Hittable(Ball(point3(1, 0, -1), 0.5, deviceMat_right)), count);
		addObject(Hittable(Ball(point3(-1, 0, -1), -0.45, deviceMat_bubble)), count);
		addObject(Hittable(Triangle(point3(-5, 0, -5), point3(5, 0, -5), point3(0, 5, -1), deviceMat_screen)), count);
	}
	break;
	case 3: {
		deviceWorld->listSize = 484;
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable) * deviceWorld->listSize);

		Texture* deviceTex_ground_odd = createTexture(textureType::SOLID, Color(0.7, 0.5, 0.3));
		Texture* deviceTex_ground_even = createTexture(textureType::SOLID, Color(0.5, 0.7, 1.0));
		Texture* deviceTex_ground = createBoardTexture(Color(0.5, 0.5, 0.5), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Material* deviceMat_ground = createMaterial(materialType::LAMBERTIAN, deviceTex_ground);
		addObject(Hittable(Ball(point3(0, -1000, 0), 1000, deviceMat_ground)), count);


		Texture* ball_texture;
		Material* ball_material;
		for (int a = -11; a < 11; a++) {
			for (int b = -11; b < 11; b++) {
				auto choose_mat = (rand() % 0x7fff) / double(0x7fff);
				point3 center(a + 0.9 * random_double(), 0.2, b + 0.9 * random_double());

				if ((center - point3(4, 0.2, 0)).length() > 0.9) {

					if (choose_mat < 0.8) {
						// diffuse
						auto albedo = Color::random() * Color::random();
						ball_texture = createTexture(textureType::IMAGE, albedo, "ImageTexture\\head3.bmp");
						ball_material = createMaterial(materialType::LAMBERTIAN, ball_texture, 0, Color(0, 0, 0));
						addObject(Hittable(Ball(center, 0.2, ball_material)), count);
					}
					else if (choose_mat < 0.95) {
						// metal
						auto albedo = Color::random(0.5, 1);
						auto fuzz = random_double(0, 0.5);
						ball_texture = createTexture(textureType::IMAGE, albedo, "ImageTexture\\earthmap.bmp");
						ball_material = createMaterial(materialType::METAL, ball_texture, fuzz, Color(0, 0, 0));
						addObject(Hittable(Ball(center, 0.2, ball_material)), count);
					}
					else {
						// glass
						ball_texture = createTexture(textureType::SOLID, Color(1, 1, 1));
						ball_material = createMaterial(materialType::GLASS, ball_texture, 1.5);
						addObject(Hittable(Ball(center, 0.2, ball_material)), count);
					}
				}
			}
		}

		auto texture1 = createTexture(textureType::SOLID, Color(1, 1, 1));
		auto material1 = createMaterial(materialType::GLASS, texture1, 1.5);
		addObject(Hittable(Ball(point3(0, 1, 0), -1.0, material1)), count);

		auto texture2 = createTexture(textureType::IMAGE, Color(0.4, 0.2, 0.1), "ImageTexture\\dog.bmp");
		auto material2 = createMaterial(materialType::LAMBERTIAN, texture2, 0, Color(0, 0, 0));
		addObject(Hittable(Ball(point3(-1.265, 1, -3.795), -1.0, material2)), count);

		auto texture3 = createTexture(textureType::IMAGE, Color(0.7, 0.6, 0.5), "ImageTexture\\earthmap.bmp");
		auto material3 = createMaterial(materialType::METAL, texture3, 0.02, Color(0, 0, 0));
		addObject(Hittable(Ball(point3(1.265, 1, 3.795), -1.0, material3)), count);
	}
	break;
	case 4: {
		deviceWorld->listSize = 20000 + 16;
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable)* deviceWorld->listSize);
		std::vector<std::vector<point3>> controlPoints = {
			{{0,0,0},  {0,0,-1},  {0,0,-2},  {0,0,-3}},
			{{1,0,0},  {1,2,-1},  {1,2,-2},  {1,0,-3}},
			{{2,0,0},  {2,2,-1},  {2,2,-2},  {2,0,-3}},
			{{3,0,0},  {3,0,-1},  {3,0,-2},  {3,0,-3}}
		};
		//std::vector<std::vector<point3>> controlPoints = {
		//	{{0,0,0},   {3,3,0},   {6,-2,0},   {9,0,0}},
		//	{{0,3,-3},  {3,-6,-3},  {6,5,-3},  {9,3,-3}},
		//	{{0,2,-6},  {3,5,-6},  {6,-4,-6},  {9,2,-6}},
		//	{{0,0,-9},  {3,-3,-9},  {6,2,-9},  {9,0,-9}}
		//};
		Texture* deviceTex_controlPoints = createTexture(textureType::SOLID, Color(0.5, 0.7, 1.0));
		Material* deviceMat_controlPoints = createMaterial(materialType::LAMBERTIAN, deviceTex_controlPoints);
		for (int i = 0; i < 4; i++) {
			for (int j = 0; j < 4; j++) {
				addObject(Hittable(Ball(controlPoints[i][j], 0.05, deviceMat_controlPoints)), count);
			}
		}

		Texture* deviceTex_bezier_odd = createTexture(textureType::NOISE, Color(1, 0, 0), nullptr, 0.2, 7);
		Texture* deviceTex_bezier_even = createTexture(textureType::NOISE, Color(0, 1, 0), nullptr, 0.2, 7, deviceTex_bezier_odd->noise.perlin);
		Texture* deviceTex_bezier = createBoardTexture(Color(1, 1, 1), 0.1, deviceTex_bezier_odd, deviceTex_bezier_even);
		Material* deviceMat_bezier = createMaterial(materialType::METAL, deviceTex_bezier, 0, Color(0.5, 0.5, 0.5));
		//addBezierSurfaces(controlPoints, &deviceMat_bezier, 1, count);
		addBSplineSurfaces(controlPoints, &deviceMat_bezier, 1, count);
		//Texture* deviceTex_random[100];
		//for (int i = 0; i < 100; i++) {
		//	deviceTex_random[i] = createTexture(textureType::SOLID, Color::random());
		//}
		//Material* deviceMat_random[100];
		//for (int i = 0; i < 100; i++) {
		//	deviceMat_random[i] = createMaterial(materialType::LAMBERTIAN, deviceTex_random[i]);
		//}
		//addBezierSurfaces(controlPoints, deviceMat_random, 100, count);
	}
	break;
	case 5: {
		deviceWorld->lightSize = 1;
		cudaMallocManaged(&deviceWorld->lights, sizeof(DotLight) * deviceWorld->lightSize);
		deviceWorld->lights[0] = DotLight(point3(0, 5, 5), Color(3, 3, 3), vector3(1, 0, 0));

		std::vector<surface> surfaces_obj;
		readObj("obj\\armadillo.obj", surfaces_obj, vector3(0, 3, 0), 5);
		//readObj("obj\\bunny2k_f.obj", surfaces_obj, vector3(4, 2, 0), 2);

		deviceWorld->listSize = surfaces_obj.size() + 1; //+1 for ground
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable) * deviceWorld->listSize);

		Texture* deviceTex_armadillo = createTexture(textureType::SOLID, Color(0.2, 0.7, 0.2));
		Material* deviceMat_armadillo = createMaterial(materialType::LAMBERTIAN, deviceTex_armadillo, 0.1, Color(0, 0, 0), 10.0);
		addObjSurfaces(surfaces_obj, &deviceMat_armadillo, 1, count);

		Texture* deviceTex_ground_odd = createTexture(textureType::NOISE, Color(1, 0, 0), nullptr, 1, 7);
		Texture* deviceTex_ground_even = createTexture(textureType::NOISE, Color(0, 1, 0), nullptr, 1, 7, deviceTex_ground_odd->noise.perlin);
		Texture* deviceTex_ground = createBoardTexture(Color(1, 1, 1), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Material* deviceMat_ground = createMaterial(materialType::LAMBERTIAN, deviceTex_ground);
		addObject(Hittable(Ball(point3(0, -1000, 0), 1000, deviceMat_ground)), count);
	}
	break;
	case 6: {
		deviceWorld->lightSize = 1;
		cudaMallocManaged(&deviceWorld->lights, sizeof(DotLight) * deviceWorld->lightSize);
		deviceWorld->lights[0] = DotLight(point3(0, 5, 5), Color(3, 3, 3), vector3(1, 0, 0));

		deviceWorld->listSize = 2;
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable) * deviceWorld->listSize);

		Texture* deviceTex_ball = createTexture(textureType::SOLID, Color(0.2, 0.7, 0.2));
		Material* deviceMat_ball = createMaterial(materialType::LAMBERTIAN, deviceTex_ball, 0.1, Color(0,0,0), 10.0);
		addObject(Hittable(Ball(point3(0, 3, 0), 3, deviceMat_ball)), count);

		Texture* deviceTex_ground_odd = createTexture(textureType::NOISE, Color(1, 0, 0), nullptr, 1, 7);
		Texture* deviceTex_ground_even = createTexture(textureType::NOISE, Color(0, 1, 0), nullptr, 1, 7, deviceTex_ground_odd->noise.perlin);
		Texture* deviceTex_ground = createBoardTexture(Color(1, 1, 1), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Material* deviceMat_ground = createMaterial(materialType::LAMBERTIAN, deviceTex_ground);
		addObject(Hittable(Ball(point3(0, -1000, 0), 1000, deviceMat_ground)), count);
	}
	break;
	case 7: {
		deviceWorld->lightSize = 2;
		cudaMallocManaged(&deviceWorld->lights, sizeof(DotLight)* deviceWorld->lightSize);
		deviceWorld->lights[0] = DotLight(point3(0, 5, 10), Color(2, 2, 2), vector3(1, 0, 0));
		deviceWorld->lights[1] = DotLight(point3(0, 20, 0), Color(5, 5, 5), vector3(0, -0.5, 0));

		deviceWorld->listSize = 3;
		cudaMallocManaged(&deviceWorld->objects, sizeof(Hittable)* deviceWorld->listSize);

		Texture* deviceTex_cylinder = createTexture(textureType::SOLID, Color(0.2, 0.7, 0.2));
		Material* deviceMat_cylinder = createMaterial(materialType::LAMBERTIAN, deviceTex_cylinder, 0.1, Color(0, 0, 0), 10.0);
		addObject(Hittable(Cylinder(point3(0, 1, 0), point3(3, 11, 0), 2, vector3(0, 1, 0), deviceMat_cylinder)), count);

		Texture* deviceTex_cylinder2 = createTexture(textureType::SOLID, Color(0.7, 0.2, 0.2));
		Material* deviceMat_cylinder2 = createMaterial(materialType::LAMBERTIAN, deviceTex_cylinder2, 0.1, Color(0, 0, 0), 10.0);
		addObject(Hittable(Cylinder(point3(5, 1, 0), point3(-2, 11, 0), 1, deviceMat_cylinder2)), count);

		Texture* deviceTex_ground_odd = createTexture(textureType::NOISE, Color(1, 0, 0), nullptr, 1, 7);
		Texture* deviceTex_ground_even = createTexture(textureType::NOISE, Color(0, 1, 0), nullptr, 1, 7, deviceTex_ground_odd->noise.perlin);
		Texture* deviceTex_ground = createBoardTexture(Color(1, 1, 1), 1, deviceTex_ground_odd, deviceTex_ground_even);
		Material* deviceMat_ground = createMaterial(materialType::LAMBERTIAN, deviceTex_ground);
		addObject(Hittable(Ball(point3(0, -1000, 0), 1000, deviceMat_ground)), count);

	}
	break;
	}

	if (deviceWorld->listSize >= count) {
		deviceWorld->listSize = count;
	}
	else{
		exit(3);
	}
	deviceWorld->createBoundingBoxs();

	return deviceWorld;
}

void freeWorld() {
	/*由于使用了cudaMallocManaged，所有的内存都在主机上，所以不需要手动释放
	//if (deviceWorld) {
	//	// 获取设备端BVH信息到主机
	//	HitList hostHitList;
	//	cudaMemcpy(&hostHitList, deviceWorld, sizeof(HitList), cudaMemcpyDeviceToHost);

	//	// 1. 清理材质资源（不再手动释放共享贴图）		
	//	std::vector<Hittable> host_objects(hostHitList.listSize);
	//	cudaMemcpy(host_objects.data(), deviceWorld->objects, sizeof(Hittable) * hostHitList.listSize, cudaMemcpyDeviceToHost);
	//	for (int i = 0; i < deviceWorld->listSize; ++i) {
	//		switch (host_objects[i].active_type) {
	//		case BALL:
	//			cudaFree(host_objects[i].ball.mat_ptr);
	//			break;
	//		case TRIANGLE:
	//			cudaFree(host_objects[i].triangle.mat_ptr);
	//			break;
	//		}
	//	}

	//	// 2. 显式清空贴图缓存（确保 CUDA 内存释放）
	//	{
	//		std::lock_guard<std::mutex> lock(cacheMutex);
	//		textureCache.clear();  //触发 ImageTextureDataDeleter 释放贴图资源
	//	}

	//	// Finally free the devices' world
	//	cudaFree(deviceWorld->objects);

	//	// 3. 释放BVH结构

	//	std::vector<BoundingBox> hostBBoxes(hostHitList.bboxSize);
	//	cudaFree(hostHitList.deviceLeafIndices);

	//	// 释放整个BVH数组
	//	cudaFree(hostHitList.bboxs);

	//	cudaFree(deviceWorld);
	//}
	*/
	cudaFree(deviceWorld);
	deviceWorld = nullptr;

	cudaFree(deviceStates);
	deviceStates = nullptr;

	cudaFree(deviceCamera);
	deviceCamera = nullptr;

	cudaFree(deviceBitmap);
	deviceBitmap = nullptr;

	free(hostBitmap);
	hostBitmap = nullptr;
}