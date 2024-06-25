/*
 *  MP42Utilities.c
 *  Subler
 *
 *  Created by Damiano Galassi on 30/01/09.
 *  Copyright 2022 Damiano Galassi. All rights reserved.
 *
 */

#import "MP42PrivateUtilities.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreMedia/CMTime.h>

#include <zlib.h>
#include <bzlib.h>

#import "MP42Languages.h"
#import "MP42MediaFormat.h"

#include "avcodec.h"

NSString * SRTStringFromTime( long long time, long timeScale , const char separator)
{
    NSString *SRT_string;
    int hour, minute, second, msecond;
    long long result;

    result = time / timeScale; // second

    msecond = (time % timeScale) / (timeScale / 1000.0f);
	
    second = result % 60;

    result = result / 60; // minute
    minute = result % 60;

    result = result / 60; // hour
    hour = result % 24;

    SRT_string = [NSString stringWithFormat:@"%02d:%02d:%02d%c%03d", hour, minute, second, separator, msecond]; // h:mm:ss:fff

    return SRT_string;
}

int MP4SetTrackEnabled(MP4FileHandle fileHandle, MP4TrackId trackId)
{
    return MP4SetTrackIntegerProperty(fileHandle, trackId, "tkhd.flags", (TRACK_ENABLED | TRACK_IN_MOVIE));
}

int MP4SetTrackDisabled(MP4FileHandle fileHandle, MP4TrackId trackId)
{
    return MP4SetTrackIntegerProperty(fileHandle, trackId, "tkhd.flags", (TRACK_DISABLED | TRACK_IN_MOVIE));
}

int updateTracksCount(MP4FileHandle fileHandle)
{
    MP4TrackId maxTrackId = 0;

    for (MP4TrackId i = 0; i< MP4GetNumberOfTracks(fileHandle, 0, 0); i++ )
        if (MP4FindTrackId(fileHandle, i, 0, 0) > maxTrackId)
            maxTrackId = MP4FindTrackId(fileHandle, i, 0, 0);

    return MP4SetIntegerProperty(fileHandle, "moov.mvhd.nextTrackId", maxTrackId + 1);
}

void updateMoovDuration(MP4FileHandle fileHandle)
{
    MP4TrackId trackId = 0;
    MP4Duration maxTrackDuration = 0, trackDuration = 0;

    for (MP4TrackId i = 0; i < MP4GetNumberOfTracks(fileHandle, 0, 0); i++ ) {
        trackId = MP4FindTrackId(fileHandle, i, 0, 0);
        MP4GetTrackIntegerProperty(fileHandle, trackId, "tkhd.duration", &trackDuration);
        if (maxTrackDuration < trackDuration) {
            maxTrackDuration = trackDuration;
        }
    }
    MP4SetIntegerProperty(fileHandle, "moov.mvhd.duration", maxTrackDuration);
}

void updateMajorBrand(MP42FileHandle fileHandle, NSURL *url)
{
    NSString *fileExtension = url.pathExtension;
    char *majorBrand = "mp42";

    if ([fileExtension isEqualToString:MP42FileTypeM4V]) {
        majorBrand = "M4V ";
    } else if ([fileExtension isEqualToString:MP42FileTypeM4A] ||
               [fileExtension isEqualToString:MP42FileTypeM4B] ||
               [fileExtension isEqualToString:MP42FileTypeM4R]) {
        majorBrand = "M4A ";
    }

    MP4SetStringProperty(fileHandle, "ftyp.majorBrand", majorBrand);
}

uint64_t getTrackSize(MP4FileHandle fileHandle, MP4TrackId trackId)
{
    MP4SampleId i = 1, sampleNum;
    uint64_t dataLength;
    sampleNum = MP4GetTrackNumberOfSamples(fileHandle, trackId);
    dataLength = 0;

    while (i <= sampleNum) {
        dataLength += MP4GetSampleSize(fileHandle, trackId, i);
        i++;
    }

    return dataLength;
}

MP4TrackId findChapterTrackId(MP4FileHandle fileHandle)
{
    MP4TrackId trackId = 0;
    uint64_t trackRef;

    for (MP4TrackId i = 0; i< MP4GetNumberOfTracks( fileHandle, 0, 0); i++ ) {
        trackId = MP4FindTrackId(fileHandle, i, 0, 0);
        if (MP4HaveTrackAtom(fileHandle, trackId, "tref.chap")) {
            MP4GetTrackIntegerProperty(fileHandle, trackId, "tref.chap.entries.trackId", &trackRef);
            if (trackRef > 0) {
                return (MP4TrackId)trackRef;
            }
        }
    }

    return 0;
}

MP4TrackId findChapterPreviewTrackId(MP4FileHandle fileHandle)
{
    MP4TrackId trackId = 0;
    uint64_t trackRef = 0;

    for (uint32_t i = 0; i< MP4GetNumberOfTracks( fileHandle, 0, 0); i++ ) {
        trackId = MP4FindTrackId(fileHandle, i, 0, 0);
        if (MP4HaveTrackAtom(fileHandle, trackId, "tref.chap")) {
            uint64_t entryCount = 0;
            MP4GetTrackIntegerProperty(fileHandle, trackId, "tref.chap.entryCount", &entryCount);
            if (entryCount > 1 && MP4GetTrackIntegerProperty(fileHandle, trackId, "tref.chap.entries[1].trackId", &trackRef))
                if (trackRef > 0) {
                    return (MP4TrackId)trackRef;
                }
        }
    }

    return 0;
}

void removeAllChapterTrackReferences(MP4FileHandle fileHandle)
{
    MP4TrackId trackId = 0;

    for (MP4TrackId i = 0; i< MP4GetNumberOfTracks( fileHandle, 0, 0); i++ ) {
        trackId = MP4FindTrackId(fileHandle, i, 0, 0);
        if (MP4HaveTrackAtom(fileHandle, trackId, "tref.chap")) {
            MP4RemoveAllTrackReferences(fileHandle, "tref.chap", trackId);
        }
    }
}

MP4TrackId findFirstVideoTrack(MP4FileHandle fileHandle)
{
    MP4TrackId videoTrack = 0;
    uint32_t trackNumber = MP4GetNumberOfTracks(fileHandle, 0, 0);
    if (!trackNumber) {
        return 0;
    }
    for (MP4TrackId i = 0; i < trackNumber; i++) {
        videoTrack = MP4FindTrackId(fileHandle, i, 0, 0);
        const char *trackType = MP4GetTrackType(fileHandle, videoTrack);
        if (trackType && !strcmp(trackType, MP4_VIDEO_TRACK_TYPE)) {
            return videoTrack;
        }
    }
    return 0;
}

uint16_t getFixedVideoWidth(MP4FileHandle fileHandle, MP4TrackId Id)
{
    uint16_t videoWidth = MP4GetTrackVideoWidth(fileHandle, Id);

    if (MP4HaveTrackAtom(fileHandle, Id, "mdia.minf.stbl.stsd.*.pasp")) {
        uint64_t hSpacing, vSpacing;
        MP4GetTrackIntegerProperty(fileHandle, Id, "mdia.minf.stbl.stsd.*.pasp.hSpacing", &hSpacing);
        MP4GetTrackIntegerProperty(fileHandle, Id, "mdia.minf.stbl.stsd.*.pasp.vSpacing", &vSpacing);
        if (hSpacing > 0 && vSpacing > 0) {
            videoWidth =  (uint16_t) (videoWidth / (float) vSpacing * (float) hSpacing);
        }
    }

    return videoWidth;
}

NSString * getTrackName(MP4FileHandle fileHandle, MP4TrackId Id)
{
    char *trackName;

    if (MP4GetTrackName(fileHandle, Id, &trackName)) {
        NSString *name = @(trackName);
        free(trackName);
        return name;
    }
    return nil;
}

FourCharCode getTrackMediaType(MP4FileHandle fileHandle, MP4TrackId Id)
{
    const char *type = MP4GetTrackType(fileHandle, Id);
    if (type && strlen(type) == 4) {
        FourCharCode code = Str2FourCC(type);
        return code;
    }
    return kMP42MediaType_Unknown;
}

FourCharCode getTrackMediaSubType(MP4FileHandle fileHandle, MP4TrackId Id, uint32_t index)
{
    const char *type = MP4GetTrackType(fileHandle, Id);
    const char *dataName = MP4GetTrackMediaDataName(fileHandle, Id, index);
    if (dataName && strlen(dataName) == 4) {
        if (!strcmp(dataName, "avc1")) {
            return kMP42VideoCodecType_H264;
        }
        else if (!strcmp(dataName, "hvc1")) {
            return kMP42VideoCodecType_HEVC;
        }
        else if (!strcmp(dataName, "hev1")) {
            return kMP42VideoCodecType_HEVC_PSinBitstream;
        }
        else if (!strcmp(dataName, "vvc1")) {
            return kMP42VideoCodecType_VVC;
        }
        else if (!strcmp(dataName, "vvic")) {
            return kMP42VideoCodecType_VVC_PSinBitstream;
        }
        else if (!strcmp(dataName, "av01")) {
            return kMP42VideoCodecType_AV1;
        }
        else if (!strcmp(dataName, "mp4a")) {
            uint8_t audiotype = MP4GetTrackEsdsObjectTypeId(fileHandle, Id);
            if (audiotype == MP4_MPEG4_AUDIO_TYPE)
                return kMP42AudioCodecType_MPEG4AAC;
            else if (audiotype == MP4_MPEG2_AUDIO_TYPE || audiotype == MP4_MPEG1_AUDIO_TYPE)
                return kMP42AudioCodecType_MPEGLayer3;
            else if (audiotype == 0xA9)
                return kMP42AudioCodecType_DTS;
        }
        else if (!strcmp(dataName, "alac"))
            return kMP42AudioCodecType_AppleLossless;
        else if (!strcmp(dataName, "ac-3"))
            return kMP42AudioCodecType_AC3;
        else if (!strcmp(dataName, "ec-3"))
            return kMP42AudioCodecType_EnhancedAC3;
        else if (!strcmp(dataName, "twos"))
            return kMP42AudioCodecType_LinearPCM;
        else if (!strcmp(dataName, "mp4v"))
            return kMP42VideoCodecType_MPEG4Video;
        else if (!strcmp(dataName, "text"))
            return kMP42SubtitleCodecType_Text;
        else if (!strcmp(dataName, "tx3g"))
            return kMP42SubtitleCodecType_3GText;
        else if (!strcmp(dataName, "wvtt"))
            return kMP42SubtitleCodecType_WebVTT;
        else if (!strcmp(dataName, "c608"))
            return kMP42ClosedCaptionCodecType_CEA608;
        else if (!strcmp(dataName, "c708"))
            return kMP42ClosedCaptionCodecType_CEA708;
        else if (!strcmp(dataName, "samr"))
            return kMP42AudioCodecType_AMR;
        else if (!strcmp(dataName, "jpeg"))
            return kMP42VideoCodecType_JPEG;
        else if (!strcmp(dataName, "rtp "))
            return 'rtp ';
        else if (!strcmp(dataName, "drms"))
            return kMP42AudioCodecType_FairPlay;
        else if (!strcmp(dataName, "drmi"))
            return kMP42VideoCodecType_FairPlay;
        else if (!strcmp(dataName, "p608"))
            return kMP42ClosedCaptionCodecType_FairPlay;
        else if (!strcmp(dataName, "tmcd"))
            return kMP42TimeCodeFormatType_TimeCode32;
        else if (!strcmp(dataName, "mp4s") && !strcmp(type, "subp"))
            return kMP42SubtitleCodecType_VobSub;

        else {
            FourCharCode code = Str2FourCC(dataName);
            return code;
        }
    }

    return kMP42MediaType_Unknown;
}

NSString * getTrackLanguage(MP4FileHandle fileHandle, MP4TrackId Id)
{
    char lang[4] = "";
    MP4GetTrackLanguage(fileHandle, Id, lang);
    return @(lang);
}

// if the subtitle filename is something like title.en.srt or movie.fre.srt
// this function detects it and returns the subtitle language
NSString * getFilenameLanguage(CFStringRef filename)
{
	CFRange findResult;
	CFStringRef baseName = NULL;
	CFStringRef langStr = NULL;
	NSString *lang = @"en";

    MP42Languages *langManager = MP42Languages.defaultManager;

	// find and strip the extension
	findResult = CFStringFind(filename, CFSTR("."), kCFCompareBackwards);
	findResult.length = findResult.location;
	findResult.location = 0;
	baseName = CFStringCreateWithSubstring(NULL, filename, findResult);

	// then find the previous period
	findResult = CFStringFind(baseName, CFSTR("."), kCFCompareBackwards);
	findResult.location++;
	findResult.length = CFStringGetLength(baseName) - findResult.location;

	// check for 3 char language code
	if (findResult.length == 3) {
		char langCStr[4] = "";

		langStr = CFStringCreateWithSubstring(NULL, baseName, findResult);
		CFStringGetCString(langStr, langCStr, 4, kCFStringEncodingASCII);
        lang = [langManager extendedTagForISO_639_2:@(langCStr)];

		CFRelease(langStr);

		// and for a 2 char language code
	} else if (findResult.length == 2) {
		char langCStr[3] = "";

		langStr = CFStringCreateWithSubstring(NULL, baseName, findResult);
		CFStringGetCString(langStr, langCStr, 3, kCFStringEncodingASCII);
        lang = [langManager extendedTagForISO_639_1:@(langCStr)];

		CFRelease(langStr);
	}
    else if (findResult.length) {
        char langCStr[40] = "";

		langStr = CFStringCreateWithSubstring(NULL, baseName, findResult);
		CFStringGetCString(langStr, langCStr, 40, kCFStringEncodingASCII);
        lang = [langManager extendedTagForLang:@(langCStr)];

        if ([lang isEqualToString:@"und"] && [langManager validateExtendedTag:@(langCStr)]) {
            lang = @(langCStr);
        }
        
        CFRelease(langStr);
    }

	CFRelease(baseName);
	return lang;
}

NSString *guessStringLanguage(NSString *stringFromFileAtURL)
{
    // we couldn't deduce language from the fileURL
    // -> Let's look into the file itself

    NSArray *tagschemes = @[NSLinguisticTagSchemeLanguage];
    NSCountedSet *languagesSet = [NSCountedSet new];
    NSLinguisticTagger *tagger = [[NSLinguisticTagger alloc] initWithTagSchemes:tagschemes options:0];
    
    [stringFromFileAtURL enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {

        if (line.length > 1) {

            tagger.string = line;

            NSOrthography *ortho = [tagger orthographyAtIndex:0 effectiveRange:NULL];
            NSString *dominantLanguage = ortho.dominantLanguage;

            if (dominantLanguage && ![dominantLanguage isEqualToString:@"und"]) {
                [languagesSet addObject:dominantLanguage];
            }
        }
    }];

    NSArray *sortedValues = [languagesSet.allObjects sortedArrayUsingComparator:^(id obj1, id obj2) {
        NSUInteger n = [languagesSet countForObject:obj1];
        NSUInteger m = [languagesSet countForObject:obj2];
        return (n <= m)? (n < m)? NSOrderedAscending : NSOrderedSame : NSOrderedDescending;
    }];

    NSString *language = sortedValues.lastObject;
    return language ? language : nil;
}

#pragma mark -

NSTimeInterval getTrackStartOffset(MP4FileHandle fileHandle, MP4TrackId Id)
{
    NSTimeInterval offset = 0;

    for (uint32_t i = 1, trackEditCount = MP4GetTrackNumberOfEdits(fileHandle, Id); i <= trackEditCount; i++) {
        MP4Duration editDuration = MP4GetTrackEditDuration(fileHandle, Id, i);
        MP4Timestamp editMediaTime = MP4GetTrackEditMediaStart(fileHandle, Id, i);
        //int8_t editMediaRate = MP4GetTrackEditDwell(fileHandle, Id, i);

        uint64_t editListVersion = 0;
        MP4GetTrackIntegerProperty(fileHandle, Id, "edts.elst.version", &editListVersion);

        if (editListVersion == 0 && editMediaTime == ((uint32_t)-1)) {
                offset += MP4ConvertFromMovieDuration(fileHandle, editDuration, MP4_NANOSECONDS_TIME_SCALE);
        }
        else if (editListVersion == 1 && editMediaTime == ((uint64_t)-1)) {
                offset += MP4ConvertFromMovieDuration(fileHandle, editDuration, MP4_NANOSECONDS_TIME_SCALE);
        }
        else if (i == 1) {
            offset -= MP4ConvertFromTrackDuration(fileHandle, Id, editMediaTime, MP4_NANOSECONDS_TIME_SCALE);
            // We got the first non empty edit list, so we have everything for the start offset
            break;
        }
    }

    return offset / 1000000;
}

MP4Duration getTrackDuration(MP4FileHandle fileHandle, MP4TrackId trackId)
{
    MP4Duration duration = 0;

    for (uint32_t i = 1, trackEditCount = MP4GetTrackNumberOfEdits(fileHandle, trackId); i <= trackEditCount; i++) {
        duration += MP4GetTrackEditDuration(fileHandle, trackId, i);
    }

    if (duration == 0) {
        duration = MP4ConvertFromTrackDuration(fileHandle, trackId,
                                               MP4GetTrackDuration(fileHandle, trackId),
                                               MP4GetTimeScale(fileHandle));
    }

    return duration;
}

void setTrackStartOffset(MP4FileHandle fileHandle, MP4TrackId Id, NSTimeInterval offset)
{
    uint32_t trackEditsCount = MP4GetTrackNumberOfEdits(fileHandle, Id);

    CMTime time = CMTimeMake(offset * 1000000, MP4_NANOSECONDS_TIME_SCALE);
    CMTime trackTime = CMTimeConvertScale(time, MP4GetTrackTimeScale(fileHandle, Id), kCMTimeRoundingMethod_Default);

    int64_t offset_i = trackTime.value;

    // If there isn't an existing edit list, just add some new ones at the start and do the usual stuff.
    if (offset_i && !trackEditsCount) {
        MP4Duration editDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                   Id,
                                                   MP4GetTrackDuration(fileHandle, Id),
                                                   MP4GetTimeScale(fileHandle));
        if (offset_i > 0) {
            MP4Duration delayDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                                    Id,
                                                                    offset_i,
                                                                    MP4GetTimeScale(fileHandle));

            MP4AddTrackEdit(fileHandle, Id, MP4_INVALID_EDIT_ID, -1, delayDuration, 0);
            MP4AddTrackEdit(fileHandle, Id, MP4_INVALID_EDIT_ID, 0, editDuration, 0);
        }
        else if (offset_i < 0) {
            MP4Duration delayDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                                    Id,
                                                                    -offset_i,
                                                                    MP4GetTimeScale(fileHandle));

            MP4AddTrackEdit(fileHandle, Id, MP4_INVALID_EDIT_ID, -offset_i, editDuration - delayDuration, 0);
        }
    }
    // If the mp4 contains already some edits list, try to reuse them
    else if (trackEditsCount) {
        if (offset_i >= 0) {
            // Remove all the empty edit lists
            while (MP4GetTrackNumberOfEdits(fileHandle, Id)) {
                uint64_t editListVersion = 0;
                MP4Timestamp editMediaTime = MP4GetTrackEditMediaStart(fileHandle, Id, 1);

                MP4GetTrackIntegerProperty(fileHandle, Id, "edts.elst.version", &editListVersion);
                
                if (editListVersion == 0 && editMediaTime == ((uint32_t)-1))
                    MP4DeleteTrackEdit(fileHandle, Id, 1);
                else if (editListVersion == 1 && editMediaTime == ((uint64_t)-1))
                    MP4DeleteTrackEdit(fileHandle, Id, 1);
                else {
                    if (getTrackStartOffset(fileHandle, Id) < 0) {
                        MP4Duration oldEditDuration = MP4GetTrackEditDuration(fileHandle, Id, 1);
                        MP4Duration oldEditMediaStart = MP4GetTrackEditMediaStart(fileHandle, Id, 1);
                        oldEditMediaStart = MP4ConvertFromTrackDuration(fileHandle,
                                                                        Id,
                                                                        oldEditMediaStart,
                                                                        MP4GetTimeScale(fileHandle));
                        MP4SetTrackEditDuration(fileHandle, Id, 1, oldEditDuration + oldEditMediaStart);
                        MP4SetTrackEditMediaStart(fileHandle, Id, 1, 0);

                    }
                    break;
                }
            }

            MP4Duration delayDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                                    Id,
                                                                    offset_i,
                                                                    MP4GetTimeScale(fileHandle));
            
            if (offset_i != 0)
                MP4AddTrackEdit(fileHandle, Id, 1, -1, delayDuration, 0);
        }
        else if (offset_i < 0) {
            // First remove all the empty edit lists
            while (MP4GetTrackNumberOfEdits(fileHandle, Id)) {
                uint64_t editListVersion = 0;
                MP4Timestamp editMediaTime = MP4GetTrackEditMediaStart(fileHandle, Id, 1);
                
                MP4GetTrackIntegerProperty(fileHandle, Id, "edts.elst.version", &editListVersion);
                
                if (editListVersion == 0 && editMediaTime == ((uint32_t)-1))
                    MP4DeleteTrackEdit(fileHandle, Id, 1);
                else if (editListVersion == 1 && editMediaTime == ((uint64_t)-1))
                    MP4DeleteTrackEdit(fileHandle, Id, 1);
                else
                    break;
            }
            // If there is already an edit list reuse it
            if (MP4GetTrackNumberOfEdits(fileHandle, Id)) {

                MP4Duration oldEditDuration = MP4GetTrackEditDuration(fileHandle, Id, 1);
                MP4Duration oldEditMediaStart = MP4GetTrackEditMediaStart(fileHandle, Id, 1);
                oldEditMediaStart = MP4ConvertFromTrackDuration(fileHandle,
                                                                Id,
                                                                oldEditMediaStart,
                                                                MP4GetTimeScale(fileHandle));
                MP4Duration newOffsetDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                                        Id,
                                                                        -offset_i,
                                                                        MP4GetTimeScale(fileHandle));

                MP4SetTrackEditDuration(fileHandle, Id, 1, oldEditDuration + oldEditMediaStart - newOffsetDuration);
                MP4SetTrackEditMediaStart(fileHandle, Id, 1, -offset_i);
            }
            // Else create a new one.
            else {
                MP4Duration delayDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                                        Id,
                                                                        -offset_i,
                                                                        MP4GetTimeScale(fileHandle));

                MP4AddTrackEdit(fileHandle, Id, 1, -1, delayDuration, 0);
            }
        }
    }

    // Update the duration in tkhd, the value must be the sum of the durations of all track's edits.
    MP4Duration totalDuration = getTrackDuration(fileHandle, Id);
    MP4SetTrackIntegerProperty(fileHandle, Id, "tkhd.duration", totalDuration);
    
    // Update the duration in mvhd.
    updateMoovDuration(fileHandle);
}

int copyTrackEditLists (MP4FileHandle fileHandle, MP4TrackId srcTrackId, MP4TrackId dstTrackId) {
    MP4Duration trackDuration = 0;
    uint32_t i = 1, trackEditCount = MP4GetTrackNumberOfEdits(fileHandle, srcTrackId);
    while (i <= trackEditCount) {
        MP4Timestamp editMediaStart = MP4GetTrackEditMediaStart(fileHandle, srcTrackId, i);
        MP4Duration editDuration = MP4ConvertFromMovieDuration(fileHandle,
                                                               MP4GetTrackEditDuration(fileHandle, srcTrackId, i),
                                                               MP4GetTimeScale(fileHandle));
        trackDuration += editDuration;
        int8_t editDwell = MP4GetTrackEditDwell(fileHandle, srcTrackId, i);
        
        MP4AddTrackEdit(fileHandle, dstTrackId, i, editMediaStart, editDuration, editDwell);
        i++;
    }
    if (trackEditCount)
        MP4SetTrackIntegerProperty(fileHandle, dstTrackId, "tkhd.duration", trackDuration);
    else {
        MP4Duration firstFrameOffset = MP4GetSampleRenderingOffset(fileHandle, dstTrackId, 1);
        MP4Duration editDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                               srcTrackId,
                                                               MP4GetTrackDuration(fileHandle, srcTrackId),
                                                               MP4GetTimeScale(fileHandle));
        MP4AddTrackEdit(fileHandle, dstTrackId, MP4_INVALID_EDIT_ID, firstFrameOffset,
                        editDuration, 0);
    }
    
    return 1;
}

NSError* MP42Error(NSString *description, NSString* recoverySuggestion, NSInteger code) {
    NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
    [errorDetail setValue:description
                   forKey:NSLocalizedDescriptionKey];
    [errorDetail setValue:recoverySuggestion
                   forKey:NSLocalizedRecoverySuggestionErrorKey];

    return [NSError errorWithDomain:@"MP42Error"
                                code:code
                            userInfo:errorDetail];
}

// Taken from HandBrake common.c
int yuv2rgb(int yuv)
{
    double y, Cr, Cb;
    int r, g, b;
    
    y  = (yuv >> 16) & 0xff;
    Cb = (yuv >>  8) & 0xff;
    Cr = (yuv      ) & 0xff;
    
    r = 1.164 * (y - 16)                      + 2.018 * (Cb - 128);
    g = 1.164 * (y - 16) - 0.813 * (Cr - 128) - 0.391 * (Cb - 128);
    b = 1.164 * (y - 16) + 1.596 * (Cr - 128);
    
    r = (r < 0) ? 0 : r;
    g = (g < 0) ? 0 : g;
    b = (b < 0) ? 0 : b;
    
    r = (r > 255) ? 255 : r;
    g = (g > 255) ? 255 : g;
    b = (b > 255) ? 255 : b;
    
    return (r << 16) | (g << 8) | b;
}

int rgb2yuv(int rgb)
{
    double r, g, b;
    int y, Cr, Cb;
    
    r = (rgb >> 16) & 0xff;
    g = (rgb >>  8) & 0xff;
    b = (rgb      ) & 0xff;
    
    y  =  16. + ( 0.257 * r) + (0.504 * g) + (0.098 * b);
    Cb = 128. + (-0.148 * r) - (0.291 * g) + (0.439 * b);
    Cr = 128. + ( 0.439 * r) - (0.368 * g) - (0.071 * b);
    
    y = (y < 0) ? 0 : y;
    Cb = (Cb < 0) ? 0 : Cb;
    Cr = (Cr < 0) ? 0 : Cr;
    
    y = (y > 255) ? 255 : y;
    Cb = (Cb > 255) ? 255 : Cb;
    Cr = (Cr > 255) ? 255 : Cr;
    
    return (y << 16) | (Cr << 8) | Cb;
}

void *fast_realloc_with_padding(void *ptr, unsigned int *size, unsigned int min_size)
{
    uint8_t *res = ptr;
	av_fast_malloc(&res, size, min_size + AV_INPUT_BUFFER_PADDING_SIZE);
	if (res) memset(res + min_size, 0, AV_INPUT_BUFFER_PADDING_SIZE);
	return res;
}

int DecompressZlib(uint8_t **sampleData, uint32_t *sampleSize)
{
    uint8_t* pkt_data = NULL;
    uint8_t av_unused *newpktdata;
    int pkt_size = *sampleSize;
    int result = 0;

    z_stream zstream = {0};
    if (inflateInit(&zstream) != Z_OK)
        return 0;
    zstream.next_in = *sampleData;
    zstream.avail_in = *sampleSize;
    do {
        pkt_size *= 3;
        newpktdata = av_realloc(pkt_data, pkt_size);
        if (!newpktdata) {
            inflateEnd(&zstream);
            goto failed;
        }
        pkt_data = newpktdata;
        zstream.avail_out = (unsigned int)(pkt_size - zstream.total_out);
        zstream.next_out = pkt_data + zstream.total_out;
        if (pkt_data) {
            result = inflate(&zstream, Z_NO_FLUSH);
        } else
            result = Z_MEM_ERROR;
    } while (result==Z_OK && pkt_size<10000000);
    pkt_size = (int)zstream.total_out;
    inflateEnd(&zstream);
    if (result != Z_STREAM_END) {
        if (result == Z_MEM_ERROR)
            result = 0;
        else
            result = 0;
        goto failed;
    }

    if (*sampleData)
        free(*sampleData);

    *sampleData = pkt_data;
    *sampleSize = pkt_size;
    return 1;

failed:
    av_free(pkt_data);
    return result;
}

int DecompressBzlib(uint8_t **sampleData, uint32_t *sampleSize)
{
    uint8_t* pkt_data = NULL;
    uint8_t av_unused *newpktdata;
    int pkt_size = *sampleSize;
    int result = 0;

    bz_stream bzstream = {0};
    if (BZ2_bzDecompressInit(&bzstream, 0, 0) != BZ_OK)
        return 0;
    bzstream.next_in = (char *) *sampleData;
    bzstream.avail_in = *sampleSize;
    do {
        pkt_size *= 3;
        newpktdata = av_realloc(pkt_data, pkt_size);
        if (!newpktdata) {
            BZ2_bzDecompressEnd(&bzstream);
            goto failed;
        }
        pkt_data = newpktdata;
        bzstream.avail_out = pkt_size - bzstream.total_out_lo32;
        bzstream.next_out = (char *) pkt_data + bzstream.total_out_lo32;
        if (pkt_data) {
            result = BZ2_bzDecompress(&bzstream);
        } else
            result = BZ_MEM_ERROR;
    } while (result==BZ_OK && pkt_size<10000000);
    pkt_size = bzstream.total_out_lo32;
    BZ2_bzDecompressEnd(&bzstream);
    if (result != BZ_STREAM_END) {
        if (result == BZ_MEM_ERROR)
            result = 0;
        else
            result = 0;
        goto failed;
    }

    if (*sampleData)
        free(*sampleData);

    *sampleData = pkt_data;
    *sampleSize = pkt_size;
    return 1;

failed:
    av_free(pkt_data);
    return result;
}
