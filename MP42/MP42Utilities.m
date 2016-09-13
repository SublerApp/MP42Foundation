//
//  MP42Utilities.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 16/11/13.
//  Copyright (c) 2013 Damiano Galassi. All rights reserved.
//

#import "MP42Utilities.h"
#import "MP42SubUtilities.h"

NSString * StringFromTime(long long time, long timeScale)
{
    NSString *time_string;
    int hour, minute, second, frame;
    long long result;

    result = time / timeScale; // second
    frame = time % timeScale;

    second = result % 60;

    result = result / 60; // minute
    minute = result % 60;

    result = result / 60; // hour
    hour = result;

    time_string = [NSString stringWithFormat:@"%d:%02d:%02d.%03d", hour, minute, second, frame]; // h:mm:ss.mss

    return time_string;
}

MP42Duration TimeFromString(NSString *time_string, MP42Duration timeScale)
{
    return ParseSubTime(time_string.UTF8String, timeScale, NO);
}

BOOL isTrackMuxable(FourCharCode format)
{
    FourCharCode supportedFormats[] = {kMP42VideoCodecType_HEVC,
                                       kMP42VideoCodecType_HEVC_2,
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

int isHdVideo(uint64_t width, uint64_t height)
{
    if ((width > 1280) || (height > 720))
        return 2;
    else if (((width >= 960) && (height >= 720)) || width >= 1280)
        return 1;

    return 0;
}
