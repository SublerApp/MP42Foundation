//
//  MP42Utilities.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 16/11/13.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import "MP42Utilities.h"
#import "MP42SubUtilities.h"
#import <AudioToolbox/AudioToolbox.h>

NSString * StringFromTime(long long time, int32_t timeScale)
{
    NSString *time_string;
    int minute, second, frame;
    long long result, hour;

    result = time / timeScale; // second
    frame = time % timeScale;

    second = result % 60;

    result = result / 60; // minute
    minute = result % 60;

    result = result / 60; // hour
    hour = result;

    time_string = [NSString stringWithFormat:@"%lld:%02d:%02d.%03d", hour, minute, second, frame]; // h:mm:ss.mss

    return time_string;
}

MP42Duration TimeFromString(NSString *time_string, int32_t timeScale)
{
    return ParseSubTime(time_string.UTF8String, timeScale, NO);
}

BOOL isTrackMuxable(FourCharCode format)
{
    FourCharCode supportedFormats[] = {kMP42VideoCodecType_AV1,
                                       kMP42VideoCodecType_VVC,
                                       kMP42VideoCodecType_VVC_PSinBitstream,
                                       kMP42VideoCodecType_HEVC,
                                       kMP42VideoCodecType_HEVC_PSinBitstream,
                                       kMP42VideoCodecType_DolbyVisionHEVC,
                                       kMP42VideoCodecType_DolbyVisionHEVC_PSinBitstream,
                                       kMP42VideoCodecType_H264,
                                       kMP42VideoCodecType_MPEG4Video,
                                       kMP42VideoCodecType_JPEG,
                                       kMP42VideoCodecType_PNG,
                                       kMP42AudioCodecType_MPEG4AAC,
                                       kMP42AudioCodecType_MPEG4AAC_HE,
                                       kMP42AudioCodecType_AppleLossless,
                                       kMP42AudioCodecType_AC3,
                                       kMP42AudioCodecType_EnhancedAC3,
                                       kMP42AudioCodecType_DTS,
                                       kMP42ClosedCaptionCodecType_CEA608,
                                       kMP42SubtitleCodecType_3GText,
                                       kMP42SubtitleCodecType_Text,
                                       kMP42SubtitleCodecType_VobSub,
                                       kMP42SubtitleCodecType_WebVTT,
                                       0};

    for (FourCharCode *currentFormat = supportedFormats; *currentFormat; currentFormat++) {
        if (*currentFormat == format) {
            return YES;
        }
    }

    return NO;
}

BOOL trackNeedConversion(FourCharCode format) {
    FourCharCode supportedConversionFormats[] = {kMP42AudioCodecType_Vorbis,
                                                 kMP42AudioCodecType_FLAC,
                                                 kMP42AudioCodecType_MPEGLayer1,
                                                 kMP42AudioCodecType_MPEGLayer2,
                                                 kMP42AudioCodecType_MPEGLayer3,
                                                 kMP42AudioCodecType_Opus,
                                                 kMP42AudioCodecType_TrueHD,
                                                 kMP42AudioCodecType_MLP,
                                                 kMP42SubtitleCodecType_SSA,
                                                 kMP42SubtitleCodecType_Text,
                                                 kMP42SubtitleCodecType_PGS,
                                                 kMP42AudioCodecType_LinearPCM,
                                                 0};

    for (FourCharCode *currentFormat = supportedConversionFormats; *currentFormat; currentFormat++) {
        if (*currentFormat == format) {
            return YES;
        }
    }

    return NO;
}

NSString *nameForChannelLayoutTag(UInt32 channelLayoutTag)
{
    UInt32 channelLayoutSize = sizeof(AudioChannelLayout);
    AudioChannelLayout *channelLayout = calloc(channelLayoutSize, 1);
    channelLayout->mChannelLayoutTag = channelLayoutTag;
    
    UInt32 bitmapSize = sizeof(UInt32);
    UInt32 channelBitmap;
    OSStatus err = AudioFormatGetProperty(kAudioFormatProperty_BitmapForLayoutTag,
                                          sizeof(AudioChannelLayoutTag), &channelLayout->mChannelLayoutTag,
                                          &bitmapSize, &channelBitmap);
    UInt32 channels = AudioChannelLayoutTag_GetNumberOfChannels(channelLayout->mChannelLayoutTag);
    if (err && channels == 6) {
        channelBitmap = 0x3F;
    }
    free(channelLayout);
    BOOL lfe = (channelBitmap & kAudioChannelBit_LFEScreen);
    int mainChannels = (lfe) ? channels - 1 : channels;
    NSString *desc;
    switch (mainChannels) {
        case 1:
            desc = @"Mono";
            break;
        case 2:
        case 3:
            desc = @"Stereo";
            break;
        default:
            desc = @"Surround";
            break;
    }
    return [NSString stringWithFormat:@"%@ %d.%d", desc, mainChannels, (lfe) ? 1 : 0];
}
