#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "rayTracingWithCUDA.h"
#include "framework.h"
#include "RayHit.cuh"


void rander(HWND hWnd, HDC hdc, Camera& cam, bool saveBMP, bool resized, int typeofworld);

HitList* createWorld(Camera& cam, int typeofworld);

void freeWorld();