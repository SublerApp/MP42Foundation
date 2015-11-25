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
    hour = result % 24;

    time_string = [NSString stringWithFormat:@"%d:%02d:%02d.%03d", hour, minute, second, frame]; // h:mm:ss.mss

    return time_string;
}

MP42Duration TimeFromString(NSString *time_string, MP42Duration timeScale)
{
    return ParseSubTime(time_string.UTF8String, timeScale, NO);
}

BOOL isTrackMuxable(NSString *formatName)
{
    NSArray *supportedFormats = @[MP42VideoFormatH264, MP42VideoFormatMPEG4Visual, MP42AudioFormatAAC, MP42AudioFormatHEAAC, MP42AudioFormatALAC,
                                  MP42AudioFormatAC3, MP42AudioFormatEAC3, MP42AudioFormatDTS, MP42SubtitleFormatTx3g, MP42SubtitleFormatText,
                                  MP42ClosedCaptionFormatCEA608, MP42VideoFormatJPEG, MP42SubtitleFormatVobSub];

    return [supportedFormats containsObject:formatName];
}

BOOL trackNeedConversion(NSString *formatName) {
    NSArray *supportedConversionFormats = @[MP42AudioFormatVorbis, MP42AudioFormatFLAC, MP42AudioFormatMP3,
                                            MP42AudioFormatTrueHD, MP42SubtitleFormatSSA, MP42SubtitleFormatText, MP42SubtitleFormatPGS];

    return [supportedConversionFormats containsObject:formatName];
}

int isHdVideo(uint64_t width, uint64_t height)
{
    if ((width > 1280) || (height > 720))
        return 2;
    else if (((width >= 960) && (height >= 720)) || width >= 1280)
        return 1;

    return 0;
}
