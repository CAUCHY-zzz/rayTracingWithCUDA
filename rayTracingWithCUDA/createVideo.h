#pragma once

#include <iostream>
#include <string>
#include <vector>
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <wtypes.h>
}

int createVideoFromBMP(int numofBMP, int width, int height);

bool ReadBMPtoFrame(const std::wstring& filename, AVFrame* frame, std::vector<BYTE>& pixelData);

void SaveHDCToBMP(HDC hdcMem, int width, int height, const std::wstring& filename);

#pragma pack(push, 1) // 结构体成员对齐方式
typedef struct _BMPFileHeader {
    uint16_t bfType;       // 文件类型，必须为 "BM"
    uint32_t bfSize;       // 文件大小
    uint16_t bfReserved1;  // 保留字
    uint16_t bfReserved2;  // 保留字
    uint32_t bfOffBits;    // 从文件头到实际像素数据的偏移
} BMPFileHeader;

typedef struct _BMPInfoHeader {
    uint32_t biSize;          // 信息头的大小
    int32_t  biWidth;         // 图像宽度
    int32_t  biHeight;        // 图像高度
    uint16_t biPlanes;        // 平面数，必须为 1
    uint16_t biBitCount;      // 每个像素的位数
    uint32_t biCompression;   // 压缩类型
    uint32_t biSizeImage;     // 图像大小（字节数）
    int32_t  biXPelsPerMeter;  // 水平分辨率
    int32_t  biYPelsPerMeter;  // 垂直分辨率
    uint32_t biClrUsed;       // 实际使用的颜色数
    uint32_t biClrImportant;  // 重要颜色数
} BMPInfoHeader;
#pragma pack(pop)