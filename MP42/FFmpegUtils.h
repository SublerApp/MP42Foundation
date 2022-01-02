//
//  FFmpegUtils.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#ifndef FFmpegUtils_h
#define FFmpegUtils_h

#include <Foundation/Foundation.h>
#include <CoreAudio/CoreAudio.h>
#include <avcodec.h>

enum AVCodecID ASBDToCodecID(AudioStreamBasicDescription asbd);
enum AVCodecID FourCCToCodecID(OSType formatID);
OSType CodecIDToFourCC(enum AVCodecID codecID);

int remap_layout(AudioChannelLayout *layout, uint64_t in_layout, int count);
uint64_t convert_layout_to_av(AudioChannelLayout *layout, UInt32 layoutSize);

uint64_t channel_layout_for_channels(AVCodec *codec, int channels);

#endif /* FFmpegUtils_h */
