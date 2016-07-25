//
//  FFmpegUtils.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#ifndef FFmpegUtils_h
#define FFmpegUtils_h

#include <Foundation/Foundation.h>
#include <avcodec.h>

void FFInitFFmpeg();
enum AVCodecID FourCCToCodecID(OSType formatID);
OSType CodecIDToFourCC(enum AVCodecID codecID);

void hb_ff_set_sample_fmt(AVCodecContext *context, AVCodec *codec,
                          enum AVSampleFormat request_sample_fmt);

#endif /* FFmpegUtils_h */
