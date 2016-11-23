//
//  MP42MkvFileImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import "MP42MkvImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42File.h"
#import "MP42SubUtilities.h"
#import "MP42Languages.h"

#import "MatroskaParser.h"
#import "MatroskaFile.h"
#include "avutil.h"

#import "MP42PrivateUtilities.h"
#import "MP42FormatUtilites.h"
#import "MP42Track+Muxer.h"
#import "MP42Track+Private.h"

#define SCALE_FACTOR 1000000.f

@interface MatroskaSample : NSObject {
@public
    unsigned long long startTime;
    unsigned long long endTime;
    unsigned long long filePos;
    unsigned int frameSize;
    unsigned int frameFlags;
}
@end

@implementation MatroskaSample
@end

@interface MatroskaDemuxHelper : NSObject {
    @public
    NSMutableArray<MatroskaSample *> *queue;

    uint64_t        currentTime;
    uint64_t        startTime;
    int64_t         minDisplayOffset;
    unsigned int buffer, samplesWritten, bufferFlush;

    MP42SampleBuffer *previousSample;
    SBSubSerializer *ss;
}
@end

@implementation MatroskaDemuxHelper

- (instancetype)init
{
    if ((self = [super init])) {
        queue = [[NSMutableArray alloc] init];
        startTime = INT64_MAX;
    }
    return self;
}

- (void) dealloc {
    [queue release], queue = nil;
    [ss release], ss = nil;

    [super dealloc];
}
@end

static int readMkvPacket(struct StdIoStream  *ioStream, TrackInfo *trackInfo, uint64_t FilePos, uint8_t** frame, uint32_t *FrameSize)
{
    uint8_t *packet = NULL;
    uint32_t iSize = *FrameSize;

    if (fseeko(ioStream->fp, FilePos, SEEK_SET)) {
#ifdef DEBUG
        fprintf(stderr,"fseeko(): %s\n", strerror(errno));
#endif
        return 0;
    }

    if (trackInfo->CompMethodPrivateSize != 0) {
        packet = malloc(iSize + trackInfo->CompMethodPrivateSize);
        memcpy(packet, trackInfo->CompMethodPrivate, trackInfo->CompMethodPrivateSize);
    }
    else
        packet = malloc(iSize);

    if (packet == NULL) {
        fprintf(stderr,"Out of memory\n");
        return 0;
    }

    size_t rd = fread(packet + trackInfo->CompMethodPrivateSize, 1, iSize, ioStream->fp);
    if (rd != iSize) {
        if (rd == 0) {
            if (feof(ioStream->fp)) {
#ifdef DEBUG
                fprintf(stderr,"Unexpected EOF while reading frame\n");
#endif
            }
            else {
#ifdef DEBUG
                fprintf(stderr,"Error reading frame: %s\n",strerror(errno));
#endif
            }
        } else {
#ifdef DEBUG
            fprintf(stderr,"Short read while reading frame\n");
#endif
        }

        free(packet);
        return 0;
    }

    iSize += trackInfo->CompMethodPrivateSize;

    if (trackInfo->CompEnabled) {
        switch (trackInfo->CompMethod) {
            case COMP_ZLIB:
                if (!DecompressZlib(&packet, &iSize)) {
                    free(packet);
                    return 0;
                }
                break;

            case COMP_BZIP:
                if (!DecompressBzlib(&packet, &iSize)) {
                    free(packet);
                    return 0;
                }
                break;

            // Not Implemented yet
            case COMP_LZO1X:
                break;

            default:
                break;
        }
    }

    *frame = packet;
    *FrameSize = iSize;

    return 1;
}

@implementation MP42MkvImporter {
@private
    struct MatroskaFile	*_matroskaFile;
    struct StdIoStream  *_ioStream;

    u_int64_t   _fileDuration;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"mkv", @"mka", @"mks"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)outError
{
    if ((self = [super initWithURL:fileURL])) {
        _ioStream = calloc(1, sizeof(StdIoStream));
        _matroskaFile = openMatroskaFile(self.fileURL.fileSystemRepresentation, _ioStream);

        if (!_matroskaFile) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The movie could not be opened.", @"mkv error message"),
                                      MP42LocalizedString(@"The file is not a matroska file.", @"mkv error message"), 100);
            }

            [self release];
            return nil;
        }

        NSInteger trackCount = mkv_GetNumTracks(_matroskaFile);
        NSArray<NSNumber *> *trackSizes = [self guessedTrackDataLength];

        for (NSInteger i = 0; i < trackCount; i++) {
            TrackInfo *mkvTrack = mkv_GetTrackInfo(_matroskaFile, i);
            MP42Track *newTrack = nil;

            // Video
            if (mkvTrack->Type == TT_VIDEO)  {
                float trackWidth = 0;
                newTrack = [[MP42VideoTrack alloc] init];

                [(MP42VideoTrack*)newTrack setWidth:mkvTrack->AV.Video.PixelWidth];
                [(MP42VideoTrack*)newTrack setHeight:mkvTrack->AV.Video.PixelHeight];

                AVRational dar, invPixelSize, sar;
                dar			   = (AVRational){mkvTrack->AV.Video.DisplayWidth, mkvTrack->AV.Video.DisplayHeight};
                invPixelSize   = (AVRational){mkvTrack->AV.Video.PixelHeight, mkvTrack->AV.Video.PixelWidth};
                sar = av_mul_q(dar, invPixelSize);    

                av_reduce(&sar.num, &sar.den, sar.num, sar.den, fixed1);
                
                if (sar.num && sar.den)
                    trackWidth = mkvTrack->AV.Video.PixelWidth * sar.num / sar.den;
                else
                    trackWidth = mkvTrack->AV.Video.PixelWidth;

                [(MP42VideoTrack*)newTrack setTrackWidth:trackWidth];
                [(MP42VideoTrack*)newTrack setTrackHeight:mkvTrack->AV.Video.PixelHeight];

                [(MP42VideoTrack*)newTrack setHSpacing:sar.num];
                [(MP42VideoTrack*)newTrack setVSpacing:sar.den];
            }

            // Audio
            else if (mkvTrack->Type == TT_AUDIO) {
                newTrack = [[MP42AudioTrack alloc] init];
                [(MP42AudioTrack *)newTrack setChannels:mkvTrack->AV.Audio.Channels];
                [(MP42AudioTrack *)newTrack setChannelLayoutTag:getDefaultChannelLayout(mkvTrack->AV.Audio.Channels)];
                [newTrack setAlternate_group:1];

                for (MP42Track *audioTrack in self.tracks) {
                    if ([audioTrack isMemberOfClass:[MP42AudioTrack class]])
                        newTrack.enabled = NO;
                }
            }

            // Text
            else if (mkvTrack->Type == TT_SUB) {
                newTrack = [[MP42SubtitleTrack alloc] init];
                [newTrack setAlternate_group:2];

                for (MP42Track *subtitleTrack in self.tracks) {
                    if ([subtitleTrack isMemberOfClass:[MP42SubtitleTrack class]])
                        newTrack.enabled = NO;
                }
            }

            if (newTrack) {
                newTrack.format = CodecIDToFourCC(mkvTrack);
                newTrack.trackId = i;
                newTrack.URL = self.fileURL;
                newTrack.dataLength = trackSizes[i].unsignedLongLongValue;
                if (mkvTrack->Type == TT_AUDIO) {
                    newTrack.startOffset = [self matroskaTrackStartTime:mkvTrack Id:i];
                }

                if (newTrack.format == kMP42VideoCodecType_H264) {
                    uint8_t *avcCAtom = (uint8_t *)malloc(mkvTrack->CodecPrivateSize); // mkv stores h.264 avcC in CodecPrivate
                    memcpy(avcCAtom, mkvTrack->CodecPrivate, mkvTrack->CodecPrivateSize);
                    if (mkvTrack->CodecPrivateSize >= 3) {
                        [(MP42VideoTrack*)newTrack setOrigProfile:avcCAtom[1]];
                        [(MP42VideoTrack*)newTrack setNewProfile:avcCAtom[1]];
                        [(MP42VideoTrack*)newTrack setOrigLevel:avcCAtom[3]];
                        [(MP42VideoTrack*)newTrack setNewLevel:avcCAtom[3]];
                    }
                    free(avcCAtom);
                }

                double trackTimecodeScale = mkv_TruncFloat(mkvTrack->TimecodeScale);
                SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);
                UInt64 scaledDuration = (UInt64)segInfo->Duration / SCALE_FACTOR * trackTimecodeScale;

                newTrack.duration = scaledDuration;

                if (scaledDuration > _fileDuration)
                    _fileDuration = scaledDuration;

                NSString *trackName = TrackNameToString(mkvTrack);
                if (trackName) {
                    newTrack.name = trackName;
                }
                newTrack.language = @(mkvTrack->Language);

                [self addTrack:newTrack];
                [newTrack release];
            }
        }

        Chapter *chapters;
        unsigned count;
        mkv_GetChapters(_matroskaFile, &chapters, &count);

        if (count) {
            MP42ChapterTrack *newTrack = [[MP42ChapterTrack alloc] init];
            
            SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);
            UInt64 scaledDuration = (UInt64)segInfo->Duration / SCALE_FACTOR;
            [newTrack setDuration:scaledDuration];

            if (count) {
                unsigned int xi = 0;
                for (xi = 0; xi < chapters->nChildren; xi++) {
                    uint64_t timestamp = (chapters->Children[xi].Start) / SCALE_FACTOR;
                    if (!xi)
                        timestamp = 0;
                    if (xi && timestamp == 0)
                        continue;
                    if (chapters->Children[xi].Display && strlen(chapters->Children[xi].Display->String))
                        [newTrack addChapter:[NSString stringWithUTF8String:chapters->Children[xi].Display->String]
                                    duration:timestamp];
                    else
                        [newTrack addChapter:[NSString stringWithFormat:@"Chapter %d", xi+1]
                                    duration:timestamp];
                }
            }
            [self addTrack:newTrack];
            [newTrack release];
        }

        self.metadata = [self readMatroskaMetadata];
    }

    return self;
}

- (void)addMetadataItemWithString:(NSString *)value identifier:(NSString *)identifier metadata:(MP42Metadata *)metadata
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeUnspecified
                                                      extendedLanguageTag:nil];
    [metadata addMetadataItem:item];
}

- (MP42Metadata *)readMatroskaMetadata
{
    MP42Metadata *mkvMetadata = [[[MP42Metadata alloc] init] autorelease];

    SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);
    if (segInfo->Title) {
        [self addMetadataItemWithString:[NSString stringWithUTF8String:segInfo->Title] identifier:MP42MetadataKeyName metadata:mkvMetadata];
    }
    
    Tag *tags;
    unsigned count;

    mkv_GetTags(_matroskaFile, &tags, &count);
    if (count) {
        for (unsigned int xi = 0; xi < tags->nSimpleTags; xi++) {

            if (!strcmp(tags->SimpleTags[xi].Name, "TITLE")) {
                [self addMetadataItemWithString:[NSString stringWithUTF8String:tags->SimpleTags[xi].Value] identifier:MP42MetadataKeyName metadata:mkvMetadata];
            }
            
            if (!strcmp(tags->SimpleTags[xi].Name, "DATE_RELEASED")) {
                [self addMetadataItemWithString:[NSString stringWithUTF8String:tags->SimpleTags[xi].Value] identifier:MP42MetadataKeyReleaseDate metadata:mkvMetadata];
            }

            if (!strcmp(tags->SimpleTags[xi].Name, "COMMENT")) {
                [self addMetadataItemWithString:[NSString stringWithUTF8String:tags->SimpleTags[xi].Value] identifier:MP42MetadataKeyUserComment metadata:mkvMetadata];
            }

            if (!strcmp(tags->SimpleTags[xi].Name, "DIRECTOR")) {
                [self addMetadataItemWithString:[NSString stringWithUTF8String:tags->SimpleTags[xi].Value] identifier:MP42MetadataKeyDirector metadata:mkvMetadata];
            }

            if (!strcmp(tags->SimpleTags[xi].Name, "COPYRIGHT")) {
                [self addMetadataItemWithString:[NSString stringWithUTF8String:tags->SimpleTags[xi].Value] identifier:MP42MetadataKeyCopyright metadata:mkvMetadata];
            }

            if (!strcmp(tags->SimpleTags[xi].Name, "ARTIST")) {
                [self addMetadataItemWithString:[NSString stringWithUTF8String:tags->SimpleTags[xi].Value] identifier:MP42MetadataKeyArtist metadata:mkvMetadata];
            }

            if (!strcmp(tags->SimpleTags[xi].Name, "ENCODER")) {
                [self addMetadataItemWithString:[NSString stringWithUTF8String:tags->SimpleTags[xi].Value] identifier:MP42MetadataKeyEncodingTool metadata:mkvMetadata];
            }
        }
    }

    Attachment *attachments;
    mkv_GetAttachments(_matroskaFile, &attachments, &count);

    if (count) {
        for (unsigned int xi = 0; xi < count; xi++) {
            NSLog(@"%s", attachments[xi].Name);
        }
    }

    return (mkvMetadata.items.count) ? mkvMetadata : nil;
}

- (NSArray<NSNumber *> *)guessedTrackDataLength
{
    SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);
    NSInteger trackCount = mkv_GetNumTracks(_matroskaFile);

    uint64_t    trackSizes[trackCount];
    uint64_t    trackTimestamp[trackCount];
    uint64_t    StartTime, EndTime, FilePos;
    uint32_t    Track, FrameSize, FrameFlags;

    if (trackCount) {
        for (int i = 0; i < trackCount; i++) {
            trackSizes[i] = 0;
            trackTimestamp[i] = 0;
        }

        StartTime = 0;
        int i = 0;
        while (StartTime < (segInfo->Duration / 64)) {
            if (!mkv_ReadFrame(_matroskaFile, 0, &Track, &StartTime, &EndTime, &FilePos, &FrameSize, &FrameFlags)) {
                trackSizes[Track] += FrameSize;
                trackTimestamp[Track] = StartTime;
                i++;
            }
            else {
                break;
            }
        }

        for (int j = 0; i < trackCount; i++) {
            if (trackTimestamp[j] > 0) {
                trackSizes[j] = trackSizes[j] * (segInfo->Duration / trackTimestamp[j]);
            }
        }

        mkv_Seek(_matroskaFile, 0, 0);
    }

    NSMutableArray<NSNumber *> *sizes = [NSMutableArray array];
    for (int i = 0; i < trackCount; i++) {
        [sizes addObject:@(trackSizes[i])];
    }

    return sizes;
}

// List of codec IDs we know about and that map to fourccs
static const struct {
    const char *codecID;
    FourCharCode fourCC;
} kCodecIDMap[] =
{
    { "V_MPEG1",            kMP42VideoCodecType_MPEG1Video },
    { "V_MPEG2",            kMP42VideoCodecType_MPEG2Video },
    { "V_MPEG4/ISO/SP",     kMP42VideoCodecType_MPEG4Video },
    { "V_MPEG4/ISO/ASP",    kMP42VideoCodecType_MPEG4Video },
    { "V_MPEG4/ISO/AP",     kMP42VideoCodecType_MPEG4Video },
    { "V_MPEG4/ISO/AVC",    kMP42VideoCodecType_H264 },
    { "V_MPEGH/ISO/HEVC",   kMP42VideoCodecType_HEVC_2 },
    { "V_THEORA",           kMP42VideoCodecType_Theora },
    { "V_VP8",              kMP42VideoCodecType_VP8 },
    { "V_VP9",              kMP42VideoCodecType_VP9 },
    { "V_PRORES",           kMP42VideoCodecType_AppleProRes422 },

    { "A_AAC",              kMP42AudioCodecType_MPEG4AAC },
    { "A_AAC/MPEG2/LC",     kMP42AudioCodecType_MPEG4AAC },
    { "A_AAC/MPEG4/LC",     kMP42AudioCodecType_MPEG4AAC },
    { "A_AAC/MPEG4/LC/SBR", kMP42AudioCodecType_MPEG4AAC_HE },
    { "A_AC3",              kMP42AudioCodecType_AC3 },
    { "A_EAC3",             kMP42AudioCodecType_EnhancedAC3 },
    { "A_DTS",              kMP42AudioCodecType_DTS },
    { "A_OPUS",             kMP42AudioCodecType_Opus },
    { "A_VORBIS",           kMP42AudioCodecType_Vorbis },
    { "A_FLAC",             kMP42AudioCodecType_FLAC },
    { "A_TRUEHD",           kMP42AudioCodecType_TrueHD },
    { "A_MLP",              kMP42AudioCodecType_MLP },
    { "A_MPEG/L1",          kMP42AudioCodecType_MPEGLayer1 },
    { "A_MPEG/L2",          kMP42AudioCodecType_MPEGLayer2 },
    { "A_MPEG/L3",          kMP42AudioCodecType_MPEGLayer3 },
    { "A_PCM/INT/BIG",      kMP42AudioCodecType_LinearPCM },
    { "A_PCM/INT/LIT",      kMP42AudioCodecType_LinearPCM },
    { "A_PCM/FLOAT/IEEE",   kMP42AudioCodecType_LinearPCM },


    { "S_TEXT/UTF8",        kMP42SubtitleCodecType_Text },
    { "S_TEXT/WEBVTT",      kMP42SubtitleCodecType_WebVTT },
    { "S_TEXT/ASS",         kMP42SubtitleCodecType_SSA },
    { "S_TEXT/SSA",         kMP42SubtitleCodecType_SSA },
    { "S_VOBSUB",           kMP42SubtitleCodecType_VobSub },
    { "S_HDMV/PGS",         kMP42SubtitleCodecType_PGS },

    { NULL,                 kMP42MediaType_Unknown },
};

static FourCharCode CodecIDToFourCC(TrackInfo *track)
{
    for (int i = 0; kCodecIDMap[i].fourCC != kMP42MediaType_Unknown; i++) {
        if (!strcmp(track->CodecID, kCodecIDMap[i].codecID)) {
            return kCodecIDMap[i].fourCC;
        }
    }
    return kMP42MediaType_Unknown;
}

static NSString * TrackNameToString(TrackInfo *track)
{
    if (track->Name && strlen(track->Name)) {
        return @(track->Name);
    }
    return nil;
}

- (uint64_t)matroskaTrackStartTime:(TrackInfo *)track Id:(MP4TrackId)Id
{
    uint64_t StartTime, EndTime, FilePos;
    uint32_t Track, FrameSize, FrameFlags;

    // mask other tracks because we don't need them
    unsigned long TrackMask = ~0;
    TrackMask &= ~(1l << Id);

    mkv_SetTrackMask(_matroskaFile, TrackMask);
    mkv_ReadFrame(_matroskaFile, 0, &Track, &StartTime, &EndTime, &FilePos, &FrameSize, &FrameFlags);
    mkv_Seek(_matroskaFile, 0, 0);

    return StartTime / SCALE_FACTOR;
}

- (NSUInteger)timescaleForTrack:(MP42Track *)track
{
    TrackInfo *trackInfo = mkv_GetTrackInfo(_matroskaFile, [track sourceId]);
    if (trackInfo->Type == TT_VIDEO) {
        return 100000;
    } else if (trackInfo->Type == TT_AUDIO) {
        NSUInteger sampleRate = mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq);
        if (!strcmp(trackInfo->CodecID, "A_AC3")) {
            if (sampleRate < 24000)
                return 48000;
        }
        // Sample rate is not set, so just guess one.
        if (sampleRate == 0) {
            return 48000;
        }

        return mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq);
    }

    return 1000;
}

- (NSSize)sizeForTrack:(MP42Track *)track
{
      return NSMakeSize([(MP42VideoTrack*)track width], [(MP42VideoTrack*) track height]);
}

- (NSData *)magicCookieForTrack:(MP42Track *)track
{
    TrackInfo *trackInfo = mkv_GetTrackInfo(_matroskaFile, track.sourceId);

    if ((!strcmp(trackInfo->CodecID, "A_AAC/MPEG4/LC") ||
        !strcmp(trackInfo->CodecID, "A_AAC/MPEG2/LC")) && !trackInfo->CodecPrivateSize) {
        NSMutableData *magicCookie = [[NSMutableData alloc] init];
        uint8_t aac[2];
        aac[0] = 0x11;
        aac[1] = 0x90;

        [magicCookie appendBytes:aac length:2];
        return [magicCookie autorelease];
    }
    else if (!strcmp(trackInfo->CodecID, "A_AC3") || !strcmp(trackInfo->CodecID, "A_EAC3")) {
        mkv_SetTrackMask(_matroskaFile, ~(1l << track.sourceId));

        uint64_t        StartTime, EndTime, FilePos;
        uint32_t        rt, FrameSize, FrameFlags;
        uint8_t         *frame = NULL;
        NSData *magicCookie = nil;

        if (!strcmp(trackInfo->CodecID, "A_AC3")) {
            // read first header to create track
            int firstFrame = mkv_ReadFrame(_matroskaFile, 0, &rt, &StartTime, &EndTime, &FilePos, &FrameSize, &FrameFlags);

            if (firstFrame != 0) {
                return nil;
            }

            if (readMkvPacket(_ioStream, trackInfo, FilePos, &frame, &FrameSize)) {

                // parse AC3 header
                // collect all the necessary meta information
                uint64_t fscod, frmsizecod, bsid, bsmod, acmod, lfeon;
                uint32_t lfe_offset = 4;

                fscod = (*(frame+4) >> 6) & 0x3;
                frmsizecod = (*(frame+4) & 0x3f) >> 1;
                bsid =  (*(frame+5) >> 3) & 0x1f;
                bsmod = (*(frame+5) & 0xf);
                acmod = (*(frame+6) >> 5) & 0x7;
                if (acmod == 2) {
                    lfe_offset -= 2;
                }
                else {
                    if ((acmod & 1) && acmod != 1) {
                        lfe_offset -= 2;
                    }
                    if (acmod & 4) {
                        lfe_offset -= 2;
                    }
                }
                lfeon = (*(frame+6) >> lfe_offset) & 0x1;

                NSMutableData *mutableCookie = [[NSMutableData alloc] init];
                [mutableCookie appendBytes:&fscod length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&bsid length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&bsmod length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&acmod length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&lfeon length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&frmsizecod length:sizeof(uint64_t)];

                magicCookie = mutableCookie;

                free(frame);
            }
        }

        else if (!strcmp(trackInfo->CodecID, "A_EAC3")) {

            void *context = NULL;
            SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);

            while (!mkv_ReadFrame(_matroskaFile, 0, &rt, &StartTime, &EndTime, &FilePos, &FrameSize, &FrameFlags) &&
                   StartTime < (segInfo->Duration / 64)) {

                if (readMkvPacket(_ioStream, trackInfo, FilePos, &frame, &FrameSize)) {
                    analyze_EAC3(&context, frame, FrameSize);
                    free(frame);
                }
            }

            if (context) {
                magicCookie = (NSData *)createCookie_EAC3(context);
                free(context);
            }
        }

        mkv_Seek(_matroskaFile, 0, 0);

        return [magicCookie autorelease];
    }
    else if (!strcmp(trackInfo->CodecID, "S_VOBSUB")) {
        char *string = (char *) trackInfo->CodecPrivate;
        char *palette = strnstr(string, "palette:", trackInfo->CodecPrivateSize);

        UInt32 colorPalette[32];

        if (palette != NULL) {
            sscanf(palette, "palette: %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx", 
                   (unsigned long*)&colorPalette[ 0], (unsigned long*)&colorPalette[ 1], (unsigned long*)&colorPalette[ 2], (unsigned long*)&colorPalette[ 3],
                   (unsigned long*)&colorPalette[ 4], (unsigned long*)&colorPalette[ 5], (unsigned long*)&colorPalette[ 6], (unsigned long*)&colorPalette[ 7],
                   (unsigned long*)&colorPalette[ 8], (unsigned long*)&colorPalette[ 9], (unsigned long*)&colorPalette[10], (unsigned long*)&colorPalette[11],
                   (unsigned long*)&colorPalette[12], (unsigned long*)&colorPalette[13], (unsigned long*)&colorPalette[14], (unsigned long*)&colorPalette[15]);
        }
        return [NSData dataWithBytes:colorPalette length:sizeof(UInt32)*16];
    }

    if (trackInfo->CodecPrivate && trackInfo->CodecPrivateSize) {
        return [NSData dataWithBytes:trackInfo->CodecPrivate length:trackInfo->CodecPrivateSize];
    }

    return nil;
}

- (AudioStreamBasicDescription)audioDescriptionForTrack:(MP42AudioTrack *)track
{
    TrackInfo *trackInfo = mkv_GetTrackInfo(_matroskaFile, track.sourceId);

    AudioStreamBasicDescription result;
    bzero(&result, sizeof(AudioStreamBasicDescription));

    result.mSampleRate = mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq);
    result.mBitsPerChannel = trackInfo->AV.Audio.BitDepth;
    result.mChannelsPerFrame = trackInfo->AV.Audio.Channels;

    if (!strcmp(trackInfo->CodecID, "A_PCM/INT/BIG")) {
        result.mFormatID = kAudioFormatLinearPCM;
        result.mFormatFlags +=  kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
    }
    else if (!strcmp(trackInfo->CodecID, "A_PCM/INT/LIT")) {
        result.mFormatID = kAudioFormatLinearPCM;
        result.mFormatFlags += kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    }
    else if (!strcmp(trackInfo->CodecID, "A_PCM/FLOAT/IEEE")) {
        result.mFormatID = kAudioFormatLinearPCM;
        result.mFormatFlags += kAudioFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked;
    }
    return result;
}

// Methods to extract all the samples from the active tracks at the same time
- (void)demux
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    uint64_t        StartTime, EndTime, FilePos;
    uint32_t        Track, FrameSize, FrameFlags;
    uint8_t         *frame = NULL;

    MatroskaDemuxHelper *demuxHelper = nil;
    MatroskaSample      *frameSample = nil, *currentSample = nil;
    int64_t             duration, next_duration;

    const unsigned int bufferSize = 20;

    /* mask other tracks because we don't need them */
    unsigned long TrackMask = ~0;

    NSArray<MP42Track *> *inputTracks = self.inputTracks;

    for (MP42Track *track in inputTracks) {
        TrackMask &= ~(1l << track.sourceId);
        track.muxer_helper->demuxer_context = [[MatroskaDemuxHelper alloc] init];
    }

    mkv_SetTrackMask(_matroskaFile, TrackMask);

    while (!mkv_ReadFrame(_matroskaFile, 0, &Track, &StartTime, &EndTime, &FilePos, &FrameSize, &FrameFlags) && !_cancelled) {
        _progress = (StartTime / _fileDuration / 10000);
        muxer_helper *helper = NULL;

        MP42Track *track = nil;

        for (MP42Track *fTrack in inputTracks){
            if (fTrack.sourceId == Track) {
                helper = fTrack.muxer_helper;
                demuxHelper = helper->demuxer_context;
                track = fTrack;
            }
        }

        if (!demuxHelper) {
            continue;
        }

        TrackInfo *trackInfo = mkv_GetTrackInfo(_matroskaFile, Track);

        if (StartTime < demuxHelper->startTime) {
            demuxHelper->startTime = StartTime;
        }

        if (trackInfo->Type == TT_AUDIO) {
            demuxHelper->samplesWritten++;

            if (readMkvPacket(_ioStream, trackInfo, FilePos, &frame, &FrameSize)) {

                MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                sample->data = frame;
                sample->size = FrameSize;
                sample->duration = MP4_INVALID_DURATION;
                sample->offset = 0;
                sample->decodeTimestamp = StartTime;
                sample->flags |= MP42SampleBufferFlagIsSync;
                sample->trackId = track.sourceId;

#define VARIABLE_AUDIO_RATE 1

#ifdef VARIABLE_AUDIO_RATE
                if (demuxHelper->previousSample) {
                    uint64_t sampleDuration = (sample->decodeTimestamp * (double)mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq) / 1000000000.f) - demuxHelper->currentTime;

                    // MKV timestamps are a bit random, try to round them
                    // to make the sample table in the mp4 smaller.

                    // Round ac3
                    if (sampleDuration < 550 && sampleDuration > 480) {
                        sampleDuration = 512;
                    }

                    // Round aac
                    if (sampleDuration < 1060 && sampleDuration > 990) {
                        sampleDuration = 1024;
                    }

                    // Round ac3
                    if (sampleDuration < 1576 && sampleDuration > 1500) {
                        sampleDuration = 1536;
                    }

                    demuxHelper->previousSample->duration = sampleDuration;
                    [self enqueue:demuxHelper->previousSample];

                    demuxHelper->currentTime += sampleDuration;
                } else {
                    demuxHelper->currentTime = sample->decodeTimestamp * (double)mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq) / 1000000000.f;
                }

                [demuxHelper->previousSample release];
                demuxHelper->previousSample = sample;
#else
                [self enqueue:sample];
                [sample release];
#endif
            }
        }

        if (trackInfo->Type == TT_SUB) {
            if (readMkvPacket(_ioStream, trackInfo, FilePos, &frame, &FrameSize)) {
                if (strcmp(trackInfo->CodecID, "S_VOBSUB") && strcmp(trackInfo->CodecID, "S_HDMV/PGS")) {
                    if (!demuxHelper->ss) {
                        demuxHelper->ss = [[SBSubSerializer alloc] init];
                        if (!strcmp(trackInfo->CodecID, "S_TEXT/ASS") || !strcmp(trackInfo->CodecID, "S_TEXT/SSA")) {
                            [demuxHelper->ss setSSA:YES];
                        }
                    }

                    NSString *string = [[[NSString alloc] initWithBytes:frame length:FrameSize encoding:NSUTF8StringEncoding] autorelease];
                    if (!strcmp(trackInfo->CodecID, "S_TEXT/ASS") || !strcmp(trackInfo->CodecID, "S_TEXT/SSA")) {
                        string = StripSSALine(string);
                    }
                    
                    if ([string length]) {
                        SBSubLine *sl = [[SBSubLine alloc] initWithLine:string start:StartTime / SCALE_FACTOR end:EndTime / SCALE_FACTOR];
                        [demuxHelper->ss addLine:[sl autorelease]];
                    }
                    demuxHelper->samplesWritten++;
                    free(frame);
                } else {
                    MP42SampleBuffer *nextSample = [[MP42SampleBuffer alloc] init];

                    nextSample->duration = 0;
                    nextSample->offset = 0;
                    nextSample->decodeTimestamp = StartTime;
                    nextSample->data = frame;
                    nextSample->size = FrameSize;
                    nextSample->flags |= MP42SampleBufferFlagIsSync;
                    nextSample->trackId = track.sourceId;

                    // PGS are usually stored with just the start time, and blank samples to fill the gaps
                    if (!strcmp(trackInfo->CodecID, "S_HDMV/PGS")) {
                        if (!demuxHelper->previousSample) {
                            demuxHelper->previousSample = [[MP42SampleBuffer alloc] init];
                            demuxHelper->previousSample->duration = StartTime / SCALE_FACTOR;
                            demuxHelper->previousSample->offset = 0;
                            demuxHelper->previousSample->decodeTimestamp = StartTime;
                            demuxHelper->previousSample->flags |= MP42SampleBufferFlagIsSync;
                            demuxHelper->previousSample->trackId = track.sourceId;
                        } else {
                            if (nextSample->decodeTimestamp < demuxHelper->previousSample->decodeTimestamp) {
                                // Out of order samples? swap the next with the previous
                                MP42SampleBuffer *temp = nextSample;
                                nextSample = demuxHelper->previousSample;
                                demuxHelper->previousSample = temp;
                            }

                            demuxHelper->previousSample->duration = (nextSample->decodeTimestamp - demuxHelper->previousSample->decodeTimestamp) / SCALE_FACTOR;
                        }

                        [self enqueue:demuxHelper->previousSample];
                        [demuxHelper->previousSample release];

                        demuxHelper->previousSample = nextSample;
                        demuxHelper->samplesWritten++;
                    } else if (!strcmp(trackInfo->CodecID, "S_VOBSUB")) {
                        // VobSub seems to have an end duration, and no blank samples, so create a new one each time to fill the gaps
                        if (StartTime > demuxHelper->currentTime) {
                            MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                            sample->duration = (StartTime - demuxHelper->currentTime) / SCALE_FACTOR;
                            sample->size = 2;
                            sample->data = calloc(1, 2);
                            sample->flags |= MP42SampleBufferFlagIsSync;
                            sample->trackId = track.sourceId;
                            
                            [self enqueue:sample];
                            [sample release];
                        }
                        
                        nextSample->duration = (EndTime - StartTime) / SCALE_FACTOR;
                        
                        [self enqueue:nextSample];
                        [nextSample release];
                        
                        demuxHelper->currentTime = EndTime;
                    }
                }
            }
        }

        else if (trackInfo->Type == TT_VIDEO) {

            // read frames from file
            frameSample = [[MatroskaSample alloc] init];
            frameSample->startTime = StartTime;
            frameSample->endTime = EndTime;
            frameSample->filePos = FilePos;
            frameSample->frameSize = FrameSize;
            frameSample->frameFlags = FrameFlags;
            [demuxHelper->queue addObject:frameSample];
            [frameSample release];

            if ([demuxHelper->queue count] < bufferSize) {
                continue;
            } else {
                currentSample = [demuxHelper->queue objectAtIndex:demuxHelper->buffer];

                // matroska stores only the start and end time, so we need to recreate
                // the frame duration and the offset from the start time, the end time is useless
                // duration calculation
                duration = demuxHelper->queue.lastObject->startTime - currentSample->startTime;

                for (MatroskaSample *sample in demuxHelper->queue) {
                    if (sample != currentSample && (sample->startTime >= currentSample->startTime)) {
                        if ((next_duration = (sample->startTime - currentSample->startTime)) < duration) {
                            duration = next_duration;
                        }
                    }
                }

                // offset calculation
                int64_t offset = currentSample->startTime - demuxHelper->currentTime;

                demuxHelper->currentTime += duration;

                if (readMkvPacket(_ioStream, trackInfo, currentSample->filePos, &frame, &currentSample->frameSize)) {
                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->data = frame;
                    sample->size = currentSample->frameSize;
                    sample->duration = duration / 10000.0f;
                    sample->offset = offset / 10000.0f;
                    sample->decodeTimestamp = StartTime;
                    sample->flags |= (currentSample->frameFlags & FRAME_KF) ? MP42SampleBufferFlagIsSync : 0;
                    sample->trackId = track.sourceId;

                    demuxHelper->samplesWritten++;

                    // save the minimum offset, used later to keep all the offset values positive
                    if (sample->offset < demuxHelper->minDisplayOffset) {
                        demuxHelper->minDisplayOffset = sample->offset;
                    }

                    if (demuxHelper->buffer >= bufferSize) {
                        [demuxHelper->queue removeObjectAtIndex:0];
                    }
                    if (demuxHelper->buffer < bufferSize) {
                        demuxHelper->buffer++;
                    }

                    [self enqueue:sample];
                    [sample release];
                }
                else {
                    continue;
                }
            }
        }
    }

    for (MP42Track *track in inputTracks) {
        muxer_helper *helper = track.muxer_helper;
        demuxHelper = helper->demuxer_context;

        if (demuxHelper->queue) {
            TrackInfo *trackInfo = mkv_GetTrackInfo(_matroskaFile, [track sourceId]);

            while ([demuxHelper->queue count]) {
                if (demuxHelper->bufferFlush == 1) {
                    // add a last sample to get the duration for the last frame
                    MatroskaSample *lastSample = [demuxHelper->queue lastObject];
                    for (MatroskaSample *sample in demuxHelper->queue) {
                        if (sample->startTime > lastSample->startTime)
                            lastSample = sample;
                    }
                    frameSample = [[MatroskaSample alloc] init];
                    frameSample->startTime = lastSample->endTime;
                    [demuxHelper->queue addObject:frameSample];
                    [frameSample release];
                }
                currentSample = [demuxHelper->queue objectAtIndex:demuxHelper->buffer];

                // matroska stores only the start and end time, so we need to recreate
                // the frame duration and the offset from the start time, the end time is useless
                // duration calculation
                duration = demuxHelper->queue.lastObject->startTime - currentSample->startTime;

                for (MatroskaSample *sample in demuxHelper->queue) {
                    if (sample != currentSample && (sample->startTime >= currentSample->startTime)) {
                        if ((next_duration = (sample->startTime - currentSample->startTime)) < duration) {
                            duration = next_duration;
                        }
                    }
                }

                // offset calculation
                int64_t offset = currentSample->startTime - demuxHelper->currentTime;

                demuxHelper->currentTime += duration;

                if (readMkvPacket(_ioStream, trackInfo, currentSample->filePos, &frame, &currentSample->frameSize)) {
                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->data = frame;
                    sample->size = currentSample->frameSize;
                    sample->duration = duration / 10000.0f;
                    sample->offset = offset / 10000.0f;
                    sample->decodeTimestamp = StartTime;
                    sample->flags |= (currentSample->frameFlags & FRAME_KF) ? MP42SampleBufferFlagIsSync : 0;
                    sample->trackId = track.sourceId;

                    demuxHelper->samplesWritten++;

                    // save the minimum offset, used later to keep the all the offset values positive
                    if (sample->offset < demuxHelper->minDisplayOffset) {
                        demuxHelper->minDisplayOffset = sample->offset;
                    }

                    if (demuxHelper->buffer >= bufferSize) {
                        [demuxHelper->queue removeObjectAtIndex:0];
                    }

                    [self enqueue:sample];
                    [sample release];

                    demuxHelper->bufferFlush++;
                    if (demuxHelper->bufferFlush >= bufferSize - 1) {
                        break;
                    }
                }
                else {
                    continue;
                }
            }
        }

        if (demuxHelper->ss) {
            MP42SampleBuffer *sample = nil;
            MP4TrackId dstTrackId = track.sourceId;
            SBSubSerializer *ss = demuxHelper->ss;

            [ss setFinished:YES];

            while (![ss isEmpty] && !_cancelled) {
                SBSubLine *sl = [ss getSerializedPacket];

                if ([sl->line isEqualToString:@"\n"]) {
                    sample = copyEmptySubtitleSample(dstTrackId, sl->end_time - sl->begin_time, NO);
                }
                else {
                    sample = copySubtitleSample(dstTrackId, sl->line, sl->end_time - sl->begin_time, NO, NO, YES, CGSizeMake(0, 0), 0);
                }

                if (!sample) {
                    break;
                }

                demuxHelper->currentTime += sample->duration;
                sample->decodeTimestamp = demuxHelper->currentTime;

                [self enqueue:sample];
                [sample release];

                demuxHelper->samplesWritten++;
            }
        }

        if (demuxHelper->previousSample) {
            if (track.mediaType == kMP42MediaType_Subtitle) {
                demuxHelper->previousSample->duration = 100;
            }

            [self enqueue:demuxHelper->previousSample];
            [demuxHelper->previousSample release];
            demuxHelper->previousSample = nil;
        }
    }

    [self setDone];
    [pool release];
}

- (BOOL)cleanUp:(MP4FileHandle)fileHandle
{
    for (MP42Track *track in self.outputsTracks) {
        MP42Track *inputTrack = [self inputTrackWithTrackID:track.sourceId];

        MatroskaDemuxHelper *demuxHelper = inputTrack.muxer_helper->demuxer_context;
        MP4TrackId trackId = track.trackId;

        if (demuxHelper->minDisplayOffset != 0) {

            for (unsigned int i = 1; i <= demuxHelper->samplesWritten; i++) {
                int64_t correctedOffset = MP4GetSampleRenderingOffset(fileHandle, trackId, i) - demuxHelper->minDisplayOffset;
                MP4SetSampleRenderingOffset(fileHandle,
                                            trackId,
                                            i,
                                            correctedOffset);
            }

            MP4Duration editDuration = MP4ConvertFromTrackDuration(fileHandle, trackId,
                                                                   MP4GetTrackDuration(fileHandle, trackId),
                                                                   MP4GetTimeScale(fileHandle));


            // Add an empty edit list if the first pts is not 0.
            if (demuxHelper->startTime > 0) {
                MP4Duration emptyDuration = MP4ConvertFromTrackDuration(fileHandle, trackId,
                                                                       demuxHelper->startTime / 10000.0f,
                                                                       MP4GetTimeScale(fileHandle));

                MP4AddTrackEdit(fileHandle, trackId, MP4_INVALID_EDIT_ID, -1, emptyDuration, 0);
            }

            MP4AddTrackEdit(fileHandle,
                            trackId,
                            MP4_INVALID_EDIT_ID,
                            - demuxHelper->minDisplayOffset + demuxHelper->startTime / 10000.0f,
                            editDuration,
                            0);
        }
    }

    return YES;
}

- (NSString *)description
{
    return @"Matroska demuxer";
}

- (void)dealloc
{
    closeMatroskaFile(_matroskaFile, _ioStream);
    [super dealloc];
}

@end
