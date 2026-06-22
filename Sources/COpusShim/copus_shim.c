#include "copus_shim.h"

int galt_opus_set_bitrate(OpusEncoder *enc, opus_int32 bitrate) {
    return opus_encoder_ctl(enc, OPUS_SET_BITRATE_REQUEST, bitrate);
}

opus_int32 galt_opus_get_lookahead(OpusEncoder *enc) {
    opus_int32 v = 0;
    opus_encoder_ctl(enc, OPUS_GET_LOOKAHEAD_REQUEST, &v);
    return v;
}
