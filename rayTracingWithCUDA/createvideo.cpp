#include "createVideo.h"

#define FPS 30   // 设置帧率

//https://blog.csdn.net/A_zyx0808/article/details/143764672
int createVideoFromBMP(int numofBMP, int width, int height) {
    AVFormatContext* formatContext = nullptr;

    // 1. 输出格式设置
    avformat_alloc_output_context2(&formatContext, nullptr, "mp4", "output.mp4");
    if (!formatContext) {
        std::cerr << "Could not create output context\n";
        return -1;
    }

    // 2. 创建视频流
    AVStream* videoStream = avformat_new_stream(formatContext, nullptr);
    if (!videoStream) {
        std::cerr << "Failed to create video stream\n";
        return -1;
    }

    // 3. 设置编码器
    const AVCodec* codec = avcodec_find_encoder(AV_CODEC_ID_H264);
    if (!codec) {
        std::cerr << "Codec not found\n";
        return -1;
    }

    AVCodecContext* codecContext = avcodec_alloc_context3(codec);
    codecContext->bit_rate = width * height * 4 * FPS; // 比特率
    codecContext->width = width; // 宽度
    codecContext->height = height; // 高度
    codecContext->time_base = { 1, FPS }; // 帧率
    codecContext->framerate = { FPS, 1 }; // 帧率
    codecContext->pix_fmt = AV_PIX_FMT_YUV420P; // 像素格式

    if (formatContext->oformat->flags & AVFMT_GLOBALHEADER) {
        codecContext->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    // 4. 打开编码器
    int ret = avcodec_open2(codecContext, codec, nullptr);
    if (ret < 0) {
        std::cerr << "Could not open codec\n";
        return -1;
    }

    // 5. 将编码器参数复制到流中
    avcodec_parameters_from_context(videoStream->codecpar, codecContext);
    videoStream->time_base = codecContext->time_base;

    // 6. 打开输出文件
    if (!(formatContext->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&formatContext->pb, "output.mp4", AVIO_FLAG_WRITE);
        if (ret < 0) {
            std::cerr << "Could not open output file\n";
            return -1;
        }
    }

    // 7. 写文件头
    ret = avformat_write_header(formatContext, nullptr);
    if (ret < 0) {
        std::cerr << "Error occurred when writing header\n";
        return -1;
    }

    // 8. 读取 BMP 图像并编码
    for (int i = 0; i < numofBMP; i++) {
        wchar_t filename[1024];
        swprintf(filename, sizeof(filename), L"frame/input%05d.bmp", i);

        // 读取 BMP 文件
        AVFrame* frame = av_frame_alloc();
        frame->format = AV_PIX_FMT_RGB24;
        frame->width = codecContext->width;
        frame->height = codecContext->height;

        if (av_frame_get_buffer(frame, 32) < 0) {
            std::cerr << "Could not allocate frame buffer for RGBA frame" << std::endl;
            av_frame_free(&frame);
            return -1; // 错误处理
        }// 分配内存

        std::vector<BYTE> pixelData(width * height * 4);//不知道为什么frame->data[0]的数据无法直接访问:debug00
        if (!ReadBMPtoFrame(filename, frame, pixelData)) {
            std::cerr << "Failed to read BMP file" << std::endl;
            return -1; // 处理错误
        }
        av_image_fill_arrays(frame->data, frame->linesize, pixelData.data(), AV_PIX_FMT_RGBA, width, height, 1);

         //以下代码用于读取特定像素在frame->data的位置以debug01:输出视频像素错乱，且底部全黑
         //std::cout << "aaa:" << (int)*(frame->data[0] + 0) << (int)*(frame->data[0] + 1) << (int)*(frame->data[0] + 2) << (int)*(frame->data[0] + 3) << std::endl;
         //for(int i = 0; i < width * height * 4; i++){
         //    if((int)*(frame->data[0] + i) == 222){
         //        std::cout << i << std::endl;
         //    }
         //}
        
        // 转换颜色格式
        struct SwsContext* sws_ctx = sws_getContext(
            frame->width, frame->height, AV_PIX_FMT_RGBA,
            codecContext->width, codecContext->height, codecContext->pix_fmt,
            SWS_BILINEAR, nullptr, nullptr, nullptr
        );

        AVFrame* yuvFrame = av_frame_alloc();
        yuvFrame->format = codecContext->pix_fmt;
        yuvFrame->width = codecContext->width;
        yuvFrame->height = codecContext->height;
        if (av_frame_get_buffer(yuvFrame, 32) < 0) {
            std::cerr << "Could not allocate frame buffer for YUV frame" << std::endl;
            return -1; // 处理错误
        }

        sws_scale(sws_ctx, frame->data, frame->linesize, 0, frame->height, yuvFrame->data, yuvFrame->linesize);
        sws_freeContext(sws_ctx);

        yuvFrame->pts = i; // 设置时间戳

        // 码流并写入
        ret = avcodec_send_frame(codecContext, yuvFrame);
        if (ret < 0) {
            std::cerr << "Error sending frame to encoder\n";
            return -1;
        }

        AVPacket* pkt = av_packet_alloc();
        //pkt.data = nullptr;
        while (ret >= 0) {
            ret = avcodec_receive_packet(codecContext, pkt);
            if (ret >= 0) {
                pkt->stream_index = videoStream->index;
                pkt->pts = av_rescale_q(pkt->pts, codecContext->time_base, videoStream->time_base);
                pkt->dts = av_rescale_q(pkt->dts, codecContext->time_base, videoStream->time_base);
                pkt->duration = av_rescale_q(pkt->duration, codecContext->time_base, videoStream->time_base);

                av_interleaved_write_frame(formatContext, pkt);
                av_packet_unref(pkt);
            }
        }


        av_frame_free(&frame);
        av_frame_free(&yuvFrame);
    }

    //https://blog.csdn.net/dangxw_/article/details/50974677
    // 8.1 发送NULL帧防止尾帧丢失
    // 终于完成时，发送一个nullptr，表示没有更多帧要处理
    ret = avcodec_send_frame(codecContext, nullptr);
    if (ret < 0) {
        std::cerr << "Error sending NULL frame to encoder\n";
        return -1;
    }

    // 接收剩余的所有封包
    AVPacket* pkt = av_packet_alloc();
    //av_init_packet(&pkt);
    while (true) {
        ret = avcodec_receive_packet(codecContext, pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            break; // 编码器需要更多输入帧或者已到达文件结束
        }
        else if (ret < 0) {
            std::cerr << "Error during encoding\n";
            return -1;
        }
        // 这里处理 pkt  -  缩放时间戳
        pkt->stream_index = videoStream->index;
        pkt->pts = av_rescale_q(pkt->pts, codecContext->time_base, videoStream->time_base);
        pkt->dts = av_rescale_q(pkt->dts, codecContext->time_base, videoStream->time_base);
        pkt->duration = av_rescale_q(pkt->duration, codecContext->time_base, videoStream->time_base);

        av_interleaved_write_frame(formatContext, pkt);
        av_packet_unref(pkt);
    }

    // 9. 写文件尾
    av_write_trailer(formatContext);

    // 10. 释放资源
    avcodec_free_context(&codecContext);
    if (!(formatContext->oformat->flags & AVFMT_NOFILE)) {
        avio_close(formatContext->pb);
    }
    avformat_free_context(formatContext);
    avformat_network_deinit();

    return 0;
}

//BMP文件读取函数
bool ReadBMPtoFrame(const std::wstring& filename, AVFrame* frame, std::vector<BYTE>& pixelData) {
    // 打开 BMP 文件
    HANDLE hFile = CreateFileW(filename.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hFile == INVALID_HANDLE_VALUE) {
        return false;
    }

    // 读取 BMP 文件头和信息头
    BMPFileHeader bfh;
    BMPInfoHeader bih;

    DWORD bytesRead;
    ReadFile(hFile, &bfh, sizeof(bfh), &bytesRead, nullptr);
    ReadFile(hFile, &bih, sizeof(bih), &bytesRead, nullptr);

    // 判断 BMP 格式是否有效
    if (bfh.bfType != 0x4D42) {
        CloseHandle(hFile);
        return false;
    }

    // 确保图像是 32 位 RGBA
    if (bih.biBitCount != 32) {
        CloseHandle(hFile);
        return false;
    }

    // 确定图像的宽度和高度
    int width = bih.biWidth;
    int height = std::abs(bih.biHeight); // 必须取绝对值，因为 BMP 高度可以是负值

    // 检查 AVFrame 是否已经分配
    if (!frame || frame->width != width || frame->height != height) {
        CloseHandle(hFile);
        return false;
    }

    // 原本frame->data的转换全部交给本函数，但pixelData在结束后析构了，导致函数外无法访问:debug00
    // 创建一个缓冲区来存储像素数据
    // std::vector<BYTE> pixelData(width * height * 4);

    // 从文件中读取像素数据，BMP 存储顺序是从底部到顶部
    size_t rowSize = width * 4; // 每行需要的字节对齐
    std::vector<BYTE> bmpData(rowSize * height);
    ReadFile(hFile, bmpData.data(), bmpData.size(), &bytesRead, nullptr);

    frame->linesize[0] = rowSize;//默认值是4320，导致后续出错:debug01

    // 转换数据到 AVFrame
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            size_t bmpIdx = y * rowSize + x * 4; // BMP 格式从下往上存储
            size_t frameIdx = y * frame->linesize[0] + x * 4; // 在 AVFrame 中的索引

            // 将 BMP 格式数据转换为 RGBA 格式
            pixelData[frameIdx] = bmpData[bmpIdx + 2];     // R
            pixelData[frameIdx + 1] = bmpData[bmpIdx + 1]; // G
            pixelData[frameIdx + 2] = bmpData[bmpIdx];     // B
            pixelData[frameIdx + 3] = bmpData[bmpIdx + 3]; // A (透明度)
        }
    }

    // 将数据复制到 AVFrame
    //av_image_fill_arrays(frame->data, frame->linesize, pixelData.data(), AV_PIX_FMT_RGBA, width, height, 1);

    // 关闭文件句柄
    CloseHandle(hFile);
    return true;
}

// BMP 文件保存函数
void SaveHDCToBMP(HDC hdcMem, int width, int height, const std::wstring& filename) {
    // 创建 BMP 文件头和信息头
    BMPFileHeader bfh;
    BMPInfoHeader bih;

    // 填充BMP文件头
    bfh.bfType = 0x4D42; // "BM"
    bfh.bfReserved1 = 0;
    bfh.bfReserved2 = 0;
    bfh.bfOffBits = sizeof(BMPFileHeader) + sizeof(BMPInfoHeader);
    bfh.bfSize = bfh.bfOffBits + width * height * 4; // 假设使用 RGBA 格式，每像素4字节

    // 填充BMP信息头
    bih.biSize = sizeof(BMPInfoHeader);
    bih.biWidth = width;
	bih.biHeight = -height;// 负数表示从上到下
    bih.biPlanes = 1;
    bih.biBitCount = 32; // 每像素32位（RGBA）
    bih.biCompression = 0; // 无压缩
    bih.biSizeImage = 0; // 此字段可设置为0
    bih.biXPelsPerMeter = 2835; // 一般 DPI 值
    bih.biYPelsPerMeter = 2835; // 一般 DPI 值
    bih.biClrUsed = 0; // 所有颜色
    bih.biClrImportant = 0; // 所有颜色

    // 打开文件
    HANDLE hFile = CreateFileW(filename.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        return; // 错误处理
    }

    DWORD written;
    // 写入 BMP 文件头和信息头
    WriteFile(hFile, &bfh, sizeof(bfh), &written, NULL);
    WriteFile(hFile, &bih, sizeof(bih), &written, NULL);

    // 创建位图数据缓冲区
    std::vector<BYTE> data(width * height * 4); // RGBA 格式

    // 从内存设备上下文中获取像素数据
    GetBitmapBits((HBITMAP)SelectObject(hdcMem, CreateCompatibleBitmap(hdcMem, width, height)), width * height * 4, data.data());

    // 写入像素数据（BMP 存储方式是从底部开始，所以需要调整）
    for (int i = 0; i < height; i++) {
        WriteFile(hFile, data.data() + i * width * 4, width * 4, &written, NULL);
    }

    // 关闭文件句柄
    CloseHandle(hFile);
}