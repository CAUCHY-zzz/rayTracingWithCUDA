#pragma once

#include "resource.h"
#include "rayTracing.cuh"

#include "vector3.cuh"
#include "RayHit.cuh"

#include <ctime>

LRESULT CALLBACK ChildWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

ATOM RegisterChildClass(HINSTANCE hInstance);

bool moveCamera(HWND hWnd, WPARAM wParam);