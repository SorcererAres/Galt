#ifndef COPUS_SHIM_H
#define COPUS_SHIM_H
#include "opus/opus.h"

/// opus_encoder_ctl 是 C 变参函数，Swift 无法直接调用；这里包装出固定签名的辅助函数。
/// 设置目标码率（bits/s）；返回 OPUS_OK(0) 或错误码。
int galt_opus_set_bitrate(OpusEncoder *enc, opus_int32 bitrate);
/// 读取编码器前瞻（lookahead）样本数（输入采样率下）；用于 Ogg pre-skip 计算。
opus_int32 galt_opus_get_lookahead(OpusEncoder *enc);

#endif
