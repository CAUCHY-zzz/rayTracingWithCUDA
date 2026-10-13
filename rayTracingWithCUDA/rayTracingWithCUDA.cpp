// rayTracingWithCUDA.cpp : 定义应用程序的入口点。
//

#include "framework.h"
#include "rayTracingWithCUDA.h"

#define MAX_LOADSTRING 100
#define SIDEBARHEIGHT 59
#define SIDEBARWIDTH 16

// 全局变量:
HINSTANCE hInst;                                // 当前实例
WCHAR szTitle[MAX_LOADSTRING];                  // 标题栏文本
WCHAR szWindowClass[MAX_LOADSTRING];            // 主窗口类名

// 此代码模块中包含的函数的前向声明:
ATOM                MyRegisterClass(HINSTANCE hInstance);
BOOL                InitInstance(HINSTANCE, int);
LRESULT CALLBACK    WndProc(HWND, UINT, WPARAM, LPARAM);
INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);

int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPWSTR    lpCmdLine,
                     _In_ int       nCmdShow)
{
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);

    // TODO: 在此处放置代码。

    // 初始化全局字符串
    LoadStringW(hInstance, IDS_APP_TITLE, szTitle, MAX_LOADSTRING);
    LoadStringW(hInstance, IDC_RAYTRACINGWITHCUDA, szWindowClass, MAX_LOADSTRING);
    MyRegisterClass(hInstance);
	RegisterChildClass(hInstance);

    // 执行应用程序初始化:
    if (!InitInstance (hInstance, nCmdShow))
    {
        return FALSE;
    }

    HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_RAYTRACINGWITHCUDA));

    MSG msg;

    // 主消息循环:
    while (GetMessage(&msg, nullptr, 0, 0))
    {
        if (!TranslateAccelerator(msg.hwnd, hAccelTable, &msg))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }

    return (int) msg.wParam;
}



//
//  函数: MyRegisterClass()
//
//  目标: 注册窗口类。
//
ATOM MyRegisterClass(HINSTANCE hInstance)
{
    WNDCLASSEXW wcex;

    wcex.cbSize = sizeof(WNDCLASSEX);

    wcex.style          = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc    = WndProc;
    wcex.cbClsExtra     = 0;
    wcex.cbWndExtra     = 0;
    wcex.hInstance      = hInstance;
    wcex.hIcon          = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_RAYTRACINGWITHCUDA));
    wcex.hCursor        = LoadCursor(nullptr, IDC_ARROW);
    wcex.hbrBackground  = (HBRUSH)(COLOR_WINDOW+1);
    wcex.lpszMenuName   = MAKEINTRESOURCEW(IDC_RAYTRACINGWITHCUDA);
    wcex.lpszClassName  = szWindowClass;
    wcex.hIconSm        = LoadIcon(wcex.hInstance, MAKEINTRESOURCE(IDI_SMALL));

    return RegisterClassExW(&wcex);
}

// 子窗口类名
const wchar_t szChildClass[] = L"ChildWindowClass";

ATOM RegisterChildClass(HINSTANCE hInstance) {
    WNDCLASSEXW wcex = { 0 };

    wcex.cbSize = sizeof(WNDCLASSEX);

    wcex.style = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc = ChildWndProc;  // 独立窗口消息处理
    wcex.cbClsExtra = 0;
    wcex.cbWndExtra = 0;
    wcex.hInstance = hInstance;
    wcex.hIcon = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_RAYTRACINGWITHCUDA));
    wcex.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wcex.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wcex.lpszClassName = szChildClass;
    wcex.hIconSm = LoadIcon(wcex.hInstance, MAKEINTRESOURCE(IDI_SMALL));

    return RegisterClassExW(&wcex);
}

//
//   函数: InitInstance(HINSTANCE, int)
//
//   目标: 保存实例句柄并创建主窗口
//
//   注释:
//
//        在此函数中，我们在全局变量中保存实例句柄并
//        创建和显示主程序窗口。
//
BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
{
   hInst = hInstance; // 将实例句柄存储在全局变量中

   // 创建独立数据窗口
   HWND hChild = CreateWindowW(
       szChildClass,
       L"独立数据窗口",
       WS_OVERLAPPEDWINDOW,
       10, 10, 200 + SIDEBARWIDTH, 340 + SIDEBARHEIGHT,  // 位置和大小
       NULL,              // 父窗口句柄
       NULL,
       hInstance,
       NULL
   );

   ShowWindow(hChild, nCmdShow);
   UpdateWindow(hChild);

   HWND hWnd = CreateWindowW(szWindowClass, szTitle, WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT, 0, CW_USEDEFAULT, 0, nullptr, nullptr, hInstance, nullptr);

   if (!hWnd)
   {
      return FALSE;
   }

   ShowWindow(hWnd, nCmdShow);
   UpdateWindow(hWnd);

   return TRUE;
}

StateofCamera camState;
double moveSpeed = 1.0;
double turnSpeed = 0.05;
double timeSpeed = 0.1;
double timeCost = 0;
bool RECODE = false;

//
//  函数: WndProc(HWND, UINT, WPARAM, LPARAM)
//
//  目标: 处理主窗口的消息。
//
//  WM_COMMAND  - 处理应用程序菜单
//  WM_PAINT    - 绘制主窗口
//  WM_DESTROY  - 发送退出消息并返回
//
//
LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    HWND hChild = FindWindowEx(NULL, NULL, szChildClass, NULL);
	static bool saveBMP = false;
    static bool SAVEFRAME = false;
    static int FRAMEcount = 0;
	static bool resized = false;

    // 创建静态内存DC和兼容位图用于保存逐行绘制结果
    static HDC hdcMem;
    static HBITMAP hbmMem;

    switch (message)
    {
    case WM_CREATE: {
        SetWindowPos(hWnd, NULL, 0, 0, 720 + SIDEBARWIDTH, 480 + SIDEBARHEIGHT, SWP_NOZORDER | SWP_NOMOVE);

        HDC hdc = GetDC(hWnd);
        RECT rect;
        GetClientRect(hWnd, &rect);

        // 创建内存 DC 和位图
        hdcMem = CreateCompatibleDC(hdc);
        hbmMem = CreateCompatibleBitmap(hdc, rect.right, rect.bottom);
        SelectObject(hdcMem, hbmMem);

        ReleaseDC(hWnd, hdc);

        camState.roll = -0.6125;
        camState.pitch = 2.125;
        camState.yaw = 0;
        camState.origin = { 16.42, 12.95, -9.3362 };
        //camState.origin = { 0,20,30 };//7
        //camState.roll = -0.45;
        //camState.origin = { 0, 3, 30 };//6
		//camState.origin = { 0, 3, 15};//5
        //camState.origin = { 1.5, 1, 4 };//4
		//camState.roll = -0.15;
		//camState.pitch = 0.0;
		//camState.yaw = 0.0;
		//camState.origin = { 0, 2, 12.6 };
        camState.focal_length = 12.6;
        camState.viewport_height = 12.6 * 2.0 / 5.0;
        camState.viewport_width = 12.6 * 3.0 / 5.0;
		camState.angleDegree = 0;
		camState.nofSubpixel = 3;
		camState.maxDepth = 30;
        camState.light = true;
		//camState.BGColor_up = Color(0.01, 0.01, 0.01);
		//camState.BGColor_down = Color(0, 0, 0);
        camState.time = -5;//6
        break;
    }
    case WM_SIZE: {
		resized = true;

        // 销毁旧资源
        if (hdcMem) DeleteDC(hdcMem);
        if (hbmMem) DeleteObject(hbmMem);

        // 按新尺寸重建
        HDC hdc = GetDC(hWnd);
        hdcMem = CreateCompatibleDC(hdc);
        hbmMem = CreateCompatibleBitmap(hdc, LOWORD(lParam), HIWORD(lParam));
        SelectObject(hdcMem, hbmMem);
        ReleaseDC(hWnd, hdc);
        break;
    }
    case WM_KEYDOWN: {
        //只有在移动相机时才刷新
        if (moveCamera(hWnd, wParam)) {
            InvalidateRect(hWnd, NULL, FALSE);
            if (hChild != NULL)
                InvalidateRect(hChild, NULL, FALSE);
        }

        switch (wParam) {
        case VK_TAB:
            saveBMP = true;
            InvalidateRect(hWnd, NULL, FALSE);
            break;
        case VK_RETURN:
			RECODE = !RECODE;
			InvalidateRect(hWnd, NULL, FALSE);
			break;
        case 'u':
        case 'U':
            moveSpeed /= 2;
            break;
        case 'i':
        case 'I':
            moveSpeed *= 2;
            break;
		case 'n':
		case 'N':
			turnSpeed /= 2;
			break;
		case 'm':
		case 'M':
			turnSpeed *= 2;
			break;
		case 'z':
		case 'Z':
			timeSpeed /= 2;
			break;
		case 'x':
		case 'X':
			timeSpeed *= 2;
			break;
        }
        if (hChild != NULL) InvalidateRect(hChild, NULL, FALSE);
        break;
    }
    case WM_COMMAND:
        {
            int wmId = LOWORD(wParam);
            // 分析菜单选择:
            switch (wmId)
            {
            case IDM_ABOUT:
                DialogBox(hInst, MAKEINTRESOURCE(IDD_ABOUTBOX), hWnd, About);
                break;
            case IDM_EXIT:
                DestroyWindow(hWnd);
                break;
            default:
                return DefWindowProc(hWnd, message, wParam, lParam);
            }
        }
        break;
    case WM_PAINT:
        {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hWnd, &ps);

			RECT clientRect;
			GetClientRect(hWnd, &clientRect);
			int clientWidth = clientRect.right - clientRect.left;
			int clientHeight = clientRect.bottom - clientRect.top;

            SelectObject(hdcMem, hbmMem);
            
			double RofCam = sqrt(camState.origin.x() * camState.origin.x() + camState.origin.z() * camState.origin.z());
            switch (-1) {
			case 0://圆周
				camState.origin.e[0] = RofCam * sin(camState.time);
				camState.origin.e[2] = RofCam * cos(camState.time);
				camState.pitch = camState.time;
				break;
			case 1://上下
                camState.origin.e[1] = 3 + camState.time;
                camState.roll = -atan(camState.time / 15);
				break;
			case 2://横滚
                camState.yaw = camState.time;
                break;
            case 3://左右
                camState.origin.e[0] = 3 * sin(camState.time);
				break;
            }

            Camera cam(camState);

			double start = clock();
			rander(hWnd, hdcMem, cam, saveBMP, resized, 1);
			resized = false;
			double end = clock();

            if(!saveBMP)
			timeCost = (end - start) / CLOCKS_PER_SEC;

            if (hChild != NULL) InvalidateRect(hChild, NULL, FALSE);

            BitBlt(hdc, 0, 0, clientWidth, clientHeight, hdcMem, 0, 0, SRCCOPY);

            EndPaint(hWnd, &ps);

            if (saveBMP) {
                saveBMP = false;
                SaveHDCToBMP(hdcMem, clientWidth, clientHeight, L"output.bmp");
            }
			//可以稍作修改(添加计时器)变为实时录制或逐帧录制
			if (RECODE) SAVEFRAME = true;
            if (SAVEFRAME && FRAMEcount < 100) {
                // 保存到 frame 文件
                wchar_t filename[300];
                swprintf_s(filename, _countof(filename), L"frame\\input%05d.bmp", FRAMEcount++);
                SaveHDCToBMP(hdcMem, clientWidth, clientHeight, filename);
				camState.time += timeSpeed;
				SAVEFRAME = false;
				if (hChild != NULL) InvalidateRect(hChild, NULL, FALSE);
				InvalidateRect(hWnd, NULL, FALSE);
            }
            else if (FRAMEcount >= 100) {
                RECODE = false;
                KillTimer(hWnd, 2);
                int result = createVideoFromBMP(100, clientWidth, clientHeight);
                if (result < 0) {
                    exit(1);
                }
                MessageBeep(0);
                KillTimer(hWnd, 1);
            }
        }
        break;
    case WM_DESTROY:
        freeWorld();
        if (hbmMem) DeleteObject(hbmMem);
        if (hdcMem) DeleteDC(hdcMem);
        PostQuitMessage(0);
        break;
    default:
        return DefWindowProc(hWnd, message, wParam, lParam);
    }
    return 0;
}

// “关于”框的消息处理程序。
INT_PTR CALLBACK About(HWND hDlg, UINT message, WPARAM wParam, LPARAM lParam)
{
    UNREFERENCED_PARAMETER(lParam);
    switch (message)
    {
    case WM_INITDIALOG:
        return (INT_PTR)TRUE;

    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK || LOWORD(wParam) == IDCANCEL)
        {
            EndDialog(hDlg, LOWORD(wParam));
            return (INT_PTR)TRUE;
        }
        break;
    }
    return (INT_PTR)FALSE;
}

LRESULT CALLBACK ChildWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hWnd, &ps);

        // 显示数据（示例）
        RECT rc;
        GetClientRect(hWnd, &rc);

        wchar_t text[30];
        swprintf_s(text, _countof(text), L"pitch: %lf", camState.pitch);
        TextOut(hdc, 10, 0, text, wcslen(text));
        swprintf_s(text, _countof(text), L"roll: %lf", camState.roll);
        TextOut(hdc, 10, 20, text, wcslen(text));
        swprintf_s(text, _countof(text), L"yaw: %lf", camState.yaw);
        TextOut(hdc, 10, 40, text, wcslen(text));
        swprintf_s(text, _countof(text), L"x: %lf", camState.origin.e[0]);
        TextOut(hdc, 10, 60, text, wcslen(text));
        swprintf_s(text, _countof(text), L"y: %lf", camState.origin.e[1]);
        TextOut(hdc, 10, 80, text, wcslen(text));
        swprintf_s(text, _countof(text), L"z: %lf", camState.origin.e[2]);
        TextOut(hdc, 10, 100, text, wcslen(text));

        swprintf_s(text, _countof(text), L"focalLenth{-+}: %lf", camState.focal_length);
        TextOut(hdc, 10, 120, text, wcslen(text));
        swprintf_s(text, _countof(text), L"angleDegree{()}: %lf", camState.angleDegree);
        TextOut(hdc, 10, 140, text, wcslen(text));
        swprintf_s(text, _countof(text), L"nofSubpixel{jk}: %03d", camState.nofSubpixel * camState.nofSubpixel);
		TextOut(hdc, 10, 160, text, wcslen(text));
		swprintf_s(text, _countof(text), L"maxDepth{op}: %02d", camState.maxDepth);
		TextOut(hdc, 10, 180, text, wcslen(text));

		swprintf_s(text, _countof(text), L"moveSpeed{ui}: %lf", moveSpeed);
		TextOut(hdc, 10, 200, text, wcslen(text));
		swprintf_s(text, _countof(text), L"turnSpeed{nm}: %lf", turnSpeed);
		TextOut(hdc, 10, 220, text, wcslen(text));
		swprintf_s(text, _countof(text), L"showBbox{f}: %s", camState.showBbox ? L"true  " : L"false");
		TextOut(hdc, 10, 240, text, wcslen(text));
        swprintf_s(text, _countof(text), L"light{Back}: %s", camState.light ? L"on  " : L"off");
        TextOut(hdc, 10, 260, text, wcslen(text));

		swprintf_s(text, _countof(text), L"Time cost: %lf", timeCost);
		TextOut(hdc, 10, 280, text, wcslen(text));

		swprintf_s(text, _countof(text), L"time{12}: %lf", camState.time);
		TextOut(hdc, 10, 300, text, wcslen(text));
		swprintf_s(text, _countof(text), L"timeSpeed{zx}: %lf", timeSpeed);
		TextOut(hdc, 10, 320, text, wcslen(text));

        swprintf_s(text, _countof(text), L"recode{return}: %s", RECODE ? L"on  " : L"off");
        TextOut(hdc, 10, 340, text, wcslen(text));

        EndPaint(hWnd, &ps);
        return 0;
    }
    default:
        return DefWindowProc(hWnd, msg, wParam, lParam);
    }
}

bool moveCamera(HWND hWnd, WPARAM wParam) {
    vector3 moveDirection = { 0, 0, 0 };
    double devide = 2.0 / 5.0;
    switch (wParam)
    {
    case '+':
    case VK_OEM_PLUS:
        camState.focal_length += moveSpeed;
        camState.viewport_height = devide * camState.focal_length;
        camState.viewport_width = 2 * devide * camState.focal_length;
        break;
    case '-':
    case VK_OEM_MINUS:
        camState.focal_length -= moveSpeed;
        camState.focal_length = camState.focal_length < 0 ? 0 : camState.focal_length;
        camState.viewport_height = devide * camState.focal_length;
        camState.viewport_width = 2 * devide * camState.focal_length;
        break;
    case '0':
        camState.angleDegree += 0.5;
        break;
    case '9':
        camState.angleDegree -= 0.5;
        camState.angleDegree = camState.angleDegree < 0 ? 0 : camState.angleDegree;
        break;
    case VK_UP:
        camState.roll += turnSpeed;
        break;
    case VK_DOWN:
        camState.roll -= turnSpeed;
        break;
    case VK_LEFT:
        camState.pitch += turnSpeed;
        break;
    case VK_RIGHT:
        camState.pitch -= turnSpeed;
        break;
        //[
    case VK_OEM_4:
        camState.yaw += turnSpeed;
        break;
        //]
    case VK_OEM_6:
        camState.yaw -= turnSpeed;
        break;
    case 'w':
    case 'W':
        moveDirection = { 0, 0, -1 };
        camState.origin += moveSpeed * Roll(moveDirection, 0, camState.pitch, 0);//Roll(moveDirection, camState.roll, camState.pitch, camState.yaw);
        //camState.origin.e[2] -= 0.1;
        break;
    case 's':
    case 'S':
        moveDirection = { 0, 0, 1 };
        camState.origin += moveSpeed * Roll(moveDirection, 0, camState.pitch, 0);//Roll(moveDirection, camState.roll, camState.pitch, camState.yaw);
        //camState.origin.e[2] += 0.1;
        break;
    case 'a':
    case 'A':
        moveDirection = { -1, 0, 0 };
        camState.origin += moveSpeed * Roll(moveDirection, 0, camState.pitch, 0);//Roll(moveDirection, camState.roll, camState.pitch, camState.yaw);
        //camState.origin.e[0] -= 0.1;
        break;
    case 'd':
    case 'D':
        moveDirection = { 1, 0, 0 };
        camState.origin += moveSpeed * Roll(moveDirection, 0, camState.pitch, 0);//Roll(moveDirection, camState.roll, camState.pitch, camState.yaw);
        //camState.origin.e[0] += 0.1;
        break;
    case VK_SPACE:
        moveDirection = { 0, 1, 0 };
        //camState.origin += moveSpeed * camState.focal_length * Roll(moveDirection, camState.roll, camState.pitch, camState.yaw);
		camState.origin.e[1] += moveSpeed;
        break;
    case VK_CONTROL:
    case VK_SHIFT:
        moveDirection = { 0, -1, 0 };
        //camState.origin += moveSpeed * camState.focal_length * Roll(moveDirection, camState.roll, camState.pitch, camState.yaw);
		camState.origin.e[1] -= moveSpeed;
        break;
    //case VK_RETURN:
    //    camState.nofSubpixel = (3 == camState.nofSubpixel ? 10 : 3);
    //    break;
    case 'j':
	case 'J':
		camState.nofSubpixel -= 1;
		camState.nofSubpixel = camState.nofSubpixel < 1 ? 1 : camState.nofSubpixel;
		break;
	case 'k':
	case 'K':
		camState.nofSubpixel += 1;
		break;
    case 'o':
	case 'O':
        camState.maxDepth -= 1;
		camState.maxDepth = camState.maxDepth < 1 ? 1 : camState.maxDepth;
		break;
	case 'p':
	case 'P':
		camState.maxDepth += 1;
		break;
    //alt
    case 'f':
	case 'F':
		camState.showBbox = !camState.showBbox;
		break;
    case VK_BACK:
        camState.BGColor_up = camState.light ? Color(0.01, 0.01, 0.01) : Color(0.5, 0.7, 1.0);
        camState.BGColor_down = camState.light ? Color(0, 0, 0) : Color(1.0, 1.0, 1.0);
        camState.light = !camState.light;
        break;
    case 'h':
    case 'H':
        SetWindowPos(hWnd, NULL, 0, 0, 1080 + SIDEBARWIDTH, 720 + SIDEBARHEIGHT, SWP_NOZORDER | SWP_NOMOVE);
        break;
    case 'g':
    case 'G':
        SetWindowPos(hWnd, NULL, 0, 0, 720 + SIDEBARWIDTH, 480 + SIDEBARHEIGHT, SWP_NOZORDER | SWP_NOMOVE);
        break;
	case '1':
		camState.time -= timeSpeed;
		break;
	case '2':
		camState.time += timeSpeed;
        break;
    default:
        return false;
        break;
    }
    return true;
}