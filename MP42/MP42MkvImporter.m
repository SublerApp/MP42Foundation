//
//  MP42MkvImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2022 Damiano Galassi All rights reserved.
//

#import "MP42MkvImporter.h"
#import "MP42FileImporter+Private.h"
#import "MP42SampleBuffer.h"

#import "MP42File.h"
#import "MP42Languages.h"

#import "MatroskaParser.h"
#import "MatroskaFile.h"
#include "avutil.h"

#import "MP42PrivateUtilities.h"
#import "MP42FormatUtilites.h"
#import "MP42Track+Private.h"

#define SCALE_FACTOR 1000000.f
#define BUFFER_SIZE 20

MP42_OBJC_DIRECT_MEMBERS
@interface MatroskaDemuxHelper : NSObject {
@public
    MP42TrackId sourceID;
    TrackInfo *trackInfo;

    NSMutableArray<MP42SampleBuffer *> *queue;

    uint32_t    timescale;
    uint64_t    currentTime;
    uint64_t    startTime;
    int64_t     minDisplayOffset;
    uint32_t    buffer, samplesWritten, bufferFlush;

    MP42SampleBuffer *previousSample;
}
@end

@implementation MatroskaDemuxHelper

- (instancetype)init
{
    self = [super init];
    if (self) {
        queue = [[NSMutableArray alloc] init];
        startTime = INT64_MAX;
    }
    return self;
}

@end

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42MkvImporter
{
    struct MatroskaFile	*_matroskaFile;
    struct StdIoStream  *_ioStream;

    u_int64_t   _fileDuration;

    NSMutableArray<MatroskaDemuxHelper *> *_helpers;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"mkv", @"mka", @"mks"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError * __autoreleasing *)outError
{
    if ((self = [super initWithURL:fileURL])) {
        _ioStream = calloc(1, sizeof(StdIoStream));
        _matroskaFile = openMatroskaFile(self.fileURL.fileSystemRepresentation, _ioStream);
        _helpers = [NSMutableArray array];

        if (!_matroskaFile) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The movie could not be opened.", @"mkv error message"),
                                      MP42LocalizedString(@"The file is not a matroska file.", @"mkv error message"), 100);
            }
            return nil;
        }

        MP42TrackId trackCount = mkv_GetNumTracks(_matroskaFile);
        NSArray<NSNumber *> *trackSizes = [self approximatedTrackDataLength];

        for (MP42TrackId i = 0; i < trackCount; i++) {
            TrackInfo *mkvTrack = mkv_GetTrackInfo(_matroskaFile, i);
            MP42Track *newTrack = nil;

            // Video
            if (mkvTrack->Type == TT_VIDEO)  {
                float trackWidth = 0;
                AVRational dar, invPixelSize, sar;

                MP42VideoTrack *videoTrack = [[MP42VideoTrack alloc] init];

                videoTrack.width  = mkvTrack->AV.Video.PixelWidth;
                videoTrack.height = mkvTrack->AV.Video.PixelHeight;

                if (mkvTrack->AV.Video.CropB || mkvTrack->AV.Video.CropT ||
                    mkvTrack->AV.Video.CropL || mkvTrack->AV.Video.CropR) {

                    videoTrack.cleanApertureWidthN = mkvTrack->AV.Video.PixelWidth - mkvTrack->AV.Video.CropL - mkvTrack->AV.Video.CropR;
                    videoTrack.cleanApertureWidthD = 1;
                    videoTrack.cleanApertureHeightN = mkvTrack->AV.Video.PixelHeight - mkvTrack->AV.Video.CropB - mkvTrack->AV.Video.CropT;
                    videoTrack.cleanApertureHeightD = 1;
                    videoTrack.horizOffN = mkvTrack->AV.Video.CropL;
                    videoTrack.horizOffD = 1;
                    videoTrack.vertOffN = mkvTrack->AV.Video.CropT;
                    videoTrack.vertOffD = 1;

                    dar			   = (AVRational){mkvTrack->AV.Video.DisplayWidth, mkvTrack->AV.Video.DisplayHeight};
                    invPixelSize   = (AVRational){(int)videoTrack.cleanApertureHeightN, (int)videoTrack.cleanApertureWidthN};
                }
                else {
                    dar			   = (AVRational){mkvTrack->AV.Video.DisplayWidth, mkvTrack->AV.Video.DisplayHeight};
                    invPixelSize   = (AVRational){mkvTrack->AV.Video.PixelHeight, mkvTrack->AV.Video.PixelWidth};
                }

                sar = av_mul_q(dar, invPixelSize);

                av_reduce(&sar.num, &sar.den, sar.num, sar.den, fixed1);

                if (sar.num && sar.den) {
                    trackWidth = invPixelSize.den * sar.num / sar.den;
                }
                else {
                    trackWidth = invPixelSize.den;
                }

                videoTrack.trackWidth = trackWidth;
                videoTrack.trackHeight = invPixelSize.num;

                videoTrack.hSpacing = sar.num;
                videoTrack.vSpacing = sar.den;

                if (mkvTrack->AV.Video.Colour.Primaries &&
                    mkvTrack->AV.Video.Colour.TransferCharacteristics &&
                    mkvTrack->AV.Video.Colour.MatrixCoefficients) {

                    videoTrack.colorPrimaries = mkvTrack->AV.Video.Colour.Primaries;
                    videoTrack.transferCharacteristics = mkvTrack->AV.Video.Colour.TransferCharacteristics;
                    videoTrack.matrixCoefficients = mkvTrack->AV.Video.Colour.MatrixCoefficients;
                }

                if (mkvTrack->AV.Video.Colour.Range) {
                    videoTrack.colorRange = mkvTrack->AV.Video.Colour.Range == 2 ? 1 : 0;
                }

                MP42MasteringDisplayMetadata mastering;
                bzero(&mastering, sizeof(MP42MasteringDisplayMetadata));

                if (mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryRChromaticityX &&
                    mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryRChromaticityY &&
                    mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryGChromaticityX &&
                    mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryGChromaticityY &&
                    mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryBChromaticityX &&
                    mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryBChromaticityY) {
                    mastering.display_primaries[0][0] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryRChromaticityX, INT_MAX);
                    mastering.display_primaries[0][1] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryRChromaticityY, INT_MAX);
                    mastering.display_primaries[1][0] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryGChromaticityX, INT_MAX);
                    mastering.display_primaries[1][1] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryGChromaticityY, INT_MAX);
                    mastering.display_primaries[2][0] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryBChromaticityX, INT_MAX);
                    mastering.display_primaries[2][1] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.PrimaryBChromaticityY, INT_MAX);
                    mastering.white_point[0] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.WhitePointChromaticityX, INT_MAX);
                    mastering.white_point[1] = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.WhitePointChromaticityY, INT_MAX);
                    mastering.has_primaries = 1;
                }

                if (mkvTrack->AV.Video.Colour.MasteringMetadata.LuminanceMin && mkvTrack->AV.Video.Colour.MasteringMetadata.LuminanceMax) {
                    mastering.min_luminance = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.LuminanceMin, INT_MAX);
                    mastering.max_luminance = mp42_d2q(mkvTrack->AV.Video.Colour.MasteringMetadata.LuminanceMax, INT_MAX);
                    mastering.has_luminance = 1;
                }

                if (mastering.has_primaries && mastering.has_luminance) {
                    videoTrack.mastering = mastering;
                }

                if (mkvTrack->AV.Video.Colour.MaxCLL && mkvTrack->AV.Video.Colour.MaxFALL)
                {
                    MP42ContentLightMetadata coll;
                    coll.MaxCLL = mkvTrack->AV.Video.Colour.MaxCLL;
                    coll.MaxFALL = mkvTrack->AV.Video.Colour.MaxFALL;
                    videoTrack.coll = coll;
                }

                for (unsigned int xi = 0; xi < mkvTrack->nBlockAdditionMappings; xi++) {
                    struct BlockAdditionMapping *blockAddition = &mkvTrack->BlockAdditionMappings[xi];

                    if (blockAddition->ID == i) {
                        if ((blockAddition->Type == 'dvcC' || blockAddition->Type == 'dvwC' || blockAddition->Type == 'dvvC') && blockAddition->Length >= 24) {
                            uint8_t *buffer = blockAddition->Data;
                            MP42DolbyVisionMetadata dv;

                            dv.versionMajor = buffer[0];
                            dv.versionMinor = buffer[1];

                            dv.profile = (buffer[2] & 0xfe) >> 1;
                            dv.level = ((buffer[2] & 0x1) << 7) + ((buffer[3] & 0xf8) >> 3);

                            dv.rpuPresentFlag = (buffer[3] & 0x4) >> 2;
                            dv.elPresentFlag = (buffer[3] & 0x2) >> 1;
                            dv.blPresentFlag = buffer[3] & 0x1;

                            dv.blSignalCompatibilityId = (buffer[4] & 0xf0) >> 4;

                            videoTrack.dolbyVision = dv;
                        }
                        else if (blockAddition->Type == 'hvcE' || blockAddition->Type == 'avcE') {
                            videoTrack.dolbyVisionELConfiguration = [NSData dataWithBytes:blockAddition->Data length:blockAddition->Length];
                        }
                    }
                }

                newTrack = videoTrack;
            }

            // Audio
            else if (mkvTrack->Type == TT_AUDIO) {
                MP42AudioTrack *audioTrack = [[MP42AudioTrack alloc] init];
                audioTrack.channels = mkvTrack->AV.Audio.Channels;
                audioTrack.channelLayoutTag = channelLayout(mkvTrack);
                audioTrack.alternateGroup = 1;
				audioTrack.sourceId = i;
				[self streamExtensionTypeForAudioTrack:audioTrack mkvTrack:mkvTrack];		//ec3ExtensionType & complexityIndex will be populated here!

                for (MP42Track *track in self.tracks) {
                    if ([track isMemberOfClass:[MP42AudioTrack class]]) {
                        newTrack.enabled = NO;
                    }
                }

                newTrack = audioTrack;
            }

            // Text
            else if (mkvTrack->Type == TT_SUB) {
                MP42SubtitleTrack *subtitlesTrack = [[MP42SubtitleTrack alloc] init];
                subtitlesTrack.alternateGroup = 2;
                subtitlesTrack.allSamplesAreForced = mkvTrack->Forced;

                for (MP42Track *track in self.tracks) {
                    if ([track isMemberOfClass:[MP42SubtitleTrack class]]) {
                        newTrack.enabled = NO;
                    }
                }

                newTrack = subtitlesTrack;
            }

            if (newTrack) {
                newTrack.format = CodecIDToFourCC(mkvTrack);

                if ([newTrack isKindOfClass:[MP42VideoTrack class]] && ((MP42VideoTrack *)newTrack).dolbyVision.profile == 5) {
                    newTrack.format = kMP42VideoCodecType_DolbyVisionHEVC_PSinBitstream;
                }

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
                        [(MP42VideoTrack *)newTrack setOrigProfile:avcCAtom[1]];
                        [(MP42VideoTrack *)newTrack setNewProfile:avcCAtom[1]];
                        [(MP42VideoTrack *)newTrack setOrigLevel:avcCAtom[3]];
                        [(MP42VideoTrack *)newTrack setNewLevel:avcCAtom[3]];
                    }
                    free(avcCAtom);
                }

                double trackTimecodeScale = mkv_TruncFloat(mkvTrack->TimecodeScale);
                SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);
                UInt64 scaledDuration = (UInt64)segInfo->Duration / SCALE_FACTOR * trackTimecodeScale;

                newTrack.timescale = timescale(mkvTrack);
                newTrack.duration = scaledDuration;

                if (scaledDuration > _fileDuration) {
                    _fileDuration = scaledDuration;
                }

                NSString *trackName = TrackNameToString(mkvTrack);
                if (trackName) {
                    newTrack.name = trackName;
                }
                if (mkvTrack->LanguageBCP47) {
                    newTrack.language = @(mkvTrack->LanguageBCP47);
                } else {
                    newTrack.language = [MP42Languages.defaultManager extendedTagForISO_639_2b:@(mkvTrack->Language)];
                }

                [self addTrack:newTrack];
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

            for (unsigned int xi = 0; xi < chapters->nChildren; xi++) {
                uint64_t timestamp = (chapters->Children[xi].Start) / SCALE_FACTOR;
                if (!xi) {
                    timestamp = 0;
                }
                if (xi && timestamp == 0) {
                    continue;
                }
                if (chapters->Children[xi].Display && strlen(chapters->Children[xi].Display->String)) {
                    [newTrack addChapter:[NSString stringWithUTF8String:chapters->Children[xi].Display->String]
                                timestamp:timestamp];
                } else {
                    [newTrack addChapter:[NSString stringWithFormat:@"Chapter %d", xi+1]
                                timestamp:timestamp];
                }
            }
            [self addTrack:newTrack];
        }

        [self.metadata mergeMetadata:[self readMatroskaMetadata]];
    }

    return self;
}

- (void)dealloc
{
    closeMatroskaFile(_matroskaFile, _ioStream);
}

#pragma mark - Metadata

#define COLLECTION 70
#define SEASON     60
#define MOVIE      50
#define PART       40
#define CHAPTER    30
#define SCENE      20
#define SHOT       10

- (void)addMetadataItem:(id)value identifier:(NSString *)identifier metadata:(MP42Metadata *)metadata
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeUnspecified
                                                      extendedLanguageTag:nil];
    [metadata addMetadataItem:item];
}

- (MP42Metadata *)readMatroskaMetadata
{
    MP42Metadata *metadata = [[MP42Metadata alloc] init];

    SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);

    if (segInfo->Title) {
        [self addMetadataItem:@(segInfo->Title)
                   identifier:MP42MetadataKeyName
                     metadata:metadata];
    }

    NSDictionary<NSString *, NSString *> *simpleMap = @{
        @"TITLE":         MP42MetadataKeyName,
        @"SUBTITLE":      MP42MetadataKeyTrackSubTitle,
        @"ALBUM":         MP42MetadataKeyAlbum,
        @"ARTIST":        MP42MetadataKeyArtist,

        @"COMMENT":       MP42MetadataKeyUserComment,
        @"GENRE":         MP42MetadataKeyUserGenre,
        @"DATE_RELEASED": MP42MetadataKeyReleaseDate,

        @"BPM":           MP42MetadataKeyBeatsPerMin,

        @"KEYWORDS":      MP42MetadataKeyKeywords,
        @"THANKS_TO":     MP42MetadataKeyThanks,
        @"COPYRIGHT":     MP42MetadataKeyCopyright,

        @"DESCRIPTION":   MP42MetadataKeyDescription,
        @"SYNOPSIS":      MP42MetadataKeyLongDescription,

        @"DIRECTOR_OF_PHOTOGRAPHY": MP42MetadataKeyArtDirector,
        @"COMPOSER":                MP42MetadataKeyComposer,
        @"ARRANGER":                MP42MetadataKeyArranger,
        @"WRITTEN_BY":              MP42MetadataKeyAuthor,
        @"LYRICS":                  MP42MetadataKeyLyrics,
        @"CONDUCTOR":               MP42MetadataKeyConductor,
        @"PUBLISHER":               MP42MetadataKeyPublisher,
        @"SOUND_ENGINEER":          MP42MetadataKeySoundEngineer,
        @"LEAD_PERFORMER":          MP42MetadataKeySoloist,

        @"PRODUCTION_STUDIO":  MP42MetadataKeyStudio,
        @"DIRECTOR":           MP42MetadataKeyDirector,
        @"PRODUCER":           MP42MetadataKeyProducer,
        @"EXECUTIVE_PRODUCER": MP42MetadataKeyExecProducer,
        @"SCREENPLAY_BY":      MP42MetadataKeyScreenwriters,

        @"ENCODER":       MP42MetadataKeyEncodingTool,
    };

    NSDictionary<NSString *, NSString *> *collectionMap = @{
        @"TITLE":         MP42MetadataKeyTVShow,
        @"COPYRIGHT":     MP42MetadataKeyCopyright,
        @"DESCRIPTION":   MP42MetadataKeySeriesDescription,
        @"SYNOPSIS":      MP42MetadataKeySeriesDescription,
    };

    NSDictionary<NSString *, NSString *> *seasonMap = @{
        @"PART_NUMBER":   MP42MetadataKeyTVSeason,
        @"DESCRIPTION":   MP42MetadataKeySeriesDescription,
        @"SYNOPSIS":      MP42MetadataKeySeriesDescription,
        @"DATE_RELEASED": MP42MetadataKeyReleaseDate
    };

    unsigned count;
    Tag *tag_groups;

    mkv_GetTags(_matroskaFile, &tag_groups, &count);

    char *total_parts = NULL;
    char *part_number = NULL;

    for (unsigned int xi = 0; xi < count; xi++) {
        Tag *tags = &tag_groups[xi];

        ulonglong UID = 0;
        NSDictionary<NSString *, NSString *> *map = simpleMap;

        if (tags->nTargetsSize) {
            struct Target *target = &tags->Targets[0];

            if (target->Type != TARGET_TYPE_VALUE) {
                continue;
            }

            UID = target->UID;

            if (UID == CHAPTER ||
                UID == SCENE   ||
                UID == SHOT) {
                continue;
            }

            if (UID == COLLECTION) {
                map = collectionMap;
            } else if (UID == SEASON) {
                map = seasonMap;
            }
        }

        for (unsigned int yi = 0; yi < tags->nSimpleTags; yi++) {
            struct SimpleTag *tag = &tags->SimpleTags[yi];

            if (tag->Name) {
                NSString *simpleTagKey = @(tag->Name);
                NSString *key = map[simpleTagKey];

                if (key && tag->Value) {
                    [self addMetadataItem:@(tag->Value)
                               identifier:key
                                 metadata:metadata];
                } else if (UID == SEASON &&
                           [simpleTagKey isEqualToString:@"TOTAL_PARTS"]) {
                    total_parts = tag->Value;
                } else if ([simpleTagKey isEqualToString:@"PART_NUMBER"]) {
                    part_number = tag->Value;
                }
            }
        }
    }

    if (part_number) {
        int track, total = 0;

        track = atoi(part_number);
        if (total_parts) {
            total = atoi(total_parts);
        }

        [self addMetadataItem:@[@(track), @(total)]
                   identifier:MP42MetadataKeyTrackNumber
                     metadata:metadata];

        [self addMetadataItem:@(track)
                   identifier:MP42MetadataKeyTVEpisodeNumber
                     metadata:metadata];

        int season = [metadata metadataItemsFilteredByIdentifier:MP42MetadataKeyTVSeason].firstObject.numberValue.intValue;
        if (season) {
            [self addMetadataItem:[NSString stringWithFormat:@"%d%02d", season, track]
                       identifier:MP42MetadataKeyTVEpisodeID
                         metadata:metadata];
        }
    }

    Attachment *attachments;
    mkv_GetAttachments(_matroskaFile, &attachments, &count);

    for (unsigned int xi = 0; xi < count; xi++) {
        Attachment *attachment = &attachments[xi];

        if (attachment->Name && attachment->MimeType && attachment->Length > 0) {
            if (!strcmp(attachment->MimeType, "image/jpeg") ||
                !strcmp(attachment->MimeType, "image/png")) {
                uint8_t *data = malloc(attachment->Length);

                if (readData(_ioStream, attachment->Position, &data, attachment->Length)) {
                    MP42TagArtworkType type = MP42_ART_JPEG;

                    if (!strcmp(attachment->MimeType, "image/png")) {
                        type = MP42_ART_PNG;
                    }

                    MP42Image *image = [[MP42Image alloc] initWithBytes:data
                                                                 length:attachment->Length
                                                                   type:type];

                    [self addMetadataItem:image
                               identifier:MP42MetadataKeyCoverArt
                                 metadata:metadata];
                }

                free(data);
            }
        }
    }

    return metadata;
}

- (NSArray<NSNumber *> *)approximatedTrackDataLength
{
    SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);
    unsigned int trackCount = mkv_GetNumTracks(_matroskaFile);

    uint64_t    trackSizes[trackCount];
    uint64_t    trackTimestamp[trackCount];
    uint64_t    StartTime, EndTime, FilePos;
    uint32_t    Track, FrameSize, FrameFlags;
    int64_t     FrameDiscard;
    char        *frame;

    if (trackCount) {
        for (unsigned int i = 0; i < trackCount; i++) {
            trackSizes[i] = 0;
            trackTimestamp[i] = 0;
        }

        StartTime = 0;
        int i = 0;
        while (StartTime < (segInfo->Duration / 64)) {
            if (!mkv_ReadFrame(_matroskaFile, 0, &Track, &StartTime, &EndTime, &FilePos, &FrameSize, &frame, &FrameFlags, &FrameDiscard, NULL, NULL, NULL)) {
                trackSizes[Track] += FrameSize;
                trackTimestamp[Track] = StartTime;
                i++;
                free(frame);
            } else {
                break;
            }
        }

        for (unsigned int j = 0; i < trackCount; i++) {
            if (trackTimestamp[j] > 0) {
                trackSizes[j] = trackSizes[j] * (segInfo->Duration / trackTimestamp[j]);
            }
        }

        mkv_Seek(_matroskaFile, 0, 0);
    }

    NSMutableArray<NSNumber *> *sizes = [NSMutableArray array];
    for (unsigned int i = 0; i < trackCount; i++) {
        [sizes addObject:@(trackSizes[i])];
    }

    return sizes;
}

static UInt32 channelLayout(TrackInfo *trackInfo) {
    if (!strcmp(trackInfo->CodecID, "A_MS/ACM")) {
        waveformatextensible_t ex;
        if (!analyze_WAVEFORMATEX(trackInfo->CodecPrivate, trackInfo->CodecPrivateSize, &ex)) {
            return readWaveChannelLayout(&ex);
        }
    }
    return getDefaultChannelLayout(trackInfo->AV.Audio.Channels);
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
    { "V_MPEGH/ISO/HEVC",   kMP42VideoCodecType_HEVC_PSinBitstream },
    { "V_MPEGI/ISO/VVC",    kMP42VideoCodecType_VVC },
    { "V_THEORA",           kMP42VideoCodecType_Theora },
    { "V_VP8",              kMP42VideoCodecType_VP8 },
    { "V_VP9",              kMP42VideoCodecType_VP9 },
    { "V_PRORES",           kMP42VideoCodecType_AppleProRes422 },
    { "V_AV1",              kMP42VideoCodecType_AV1 },

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
    { "A_ALAC",             kMP42AudioCodecType_AppleLossless },

    { "S_TEXT/UTF8",        kMP42SubtitleCodecType_Text },
    { "S_TEXT/WEBVTT",      kMP42SubtitleCodecType_WebVTT },
    { "S_TEXT/ASS",         kMP42SubtitleCodecType_SSA },
    { "S_TEXT/SSA",         kMP42SubtitleCodecType_SSA },
    { "S_SSA",              kMP42SubtitleCodecType_SSA },
    { "S_VOBSUB",           kMP42SubtitleCodecType_VobSub },
    { "S_HDMV/PGS",         kMP42SubtitleCodecType_PGS },

    { NULL,                 kMP42MediaType_Unknown },
};

static FourCharCode CodecIDToFourCC(TrackInfo *track)
{
    if (!strcmp(track->CodecID, "A_MS/ACM")) {
        waveformatextensible_t ex;
        if (!analyze_WAVEFORMATEX(track->CodecPrivate, track->CodecPrivateSize, &ex)) {
            return readWaveFormat(&ex);
        }
    } else {
        for (int i = 0; kCodecIDMap[i].fourCC != kMP42MediaType_Unknown; i++) {
            if (!strcmp(track->CodecID, kCodecIDMap[i].codecID)) {
                return kCodecIDMap[i].fourCC;
            }
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

- (double)matroskaTrackStartTime:(TrackInfo *)track Id:(MP4TrackId)Id
{
    uint64_t StartTime, EndTime, FilePos;
    uint32_t Track, FrameSize, FrameFlags;
    int64_t FrameDiscard;
    char    *frame;

    // mask other tracks because we don't need them
    unsigned long TrackMask = ~0;
    TrackMask &= ~(1l << Id);

    mkv_SetTrackMask(_matroskaFile, TrackMask);
    mkv_ReadFrame(_matroskaFile, 0, &Track, &StartTime, &EndTime, &FilePos, &FrameSize, &frame, &FrameFlags, &FrameDiscard, NULL, NULL, NULL);
    free(frame);
    mkv_Seek(_matroskaFile, 0, 0);

    TrackInfo *trackInfo = mkv_GetTrackInfo(_matroskaFile, Id);
    int64_t codecDelay = trackInfo->CodecDelay;
    /*if (codecDelay == 0 && trackInfo->Type == TT_AUDIO && !strcmp(trackInfo->CodecID, "A_AAC")) {
        NSUInteger sampleRate = mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq);
        codecDelay = 2112 * SCALE_FACTOR * 1000 / sampleRate;
    }*/

    return (((double)StartTime) - codecDelay) / SCALE_FACTOR;
}

static uint32_t timescale(TrackInfo *trackInfo)
{
    if (trackInfo->Type == TT_VIDEO) {
        return 100000;
    } else if (trackInfo->Type == TT_AUDIO) {
        NSUInteger sampleRate = mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq);
        if (!strcmp(trackInfo->CodecID, "A_AC3")) {
            if (sampleRate < 24000) {
                return 48000;
            }
        }
        // Sample rate is not set, so just guess one.
        if (sampleRate == 0) {
            return 48000;
        }

        return mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq);
    }

    return 1000;
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
        return magicCookie;
    }
    else if (!strcmp(trackInfo->CodecID, "A_AC3") || !strcmp(trackInfo->CodecID, "A_EAC3")) {
        mkv_SetTrackMask(_matroskaFile, ~(1l << track.sourceId));

        uint64_t    StartTime, EndTime, FilePos;
        uint32_t    rt, FrameSize, FrameFlags;
        int64_t     FrameDiscard;
        char       *Frame = NULL;
        NSData     *magicCookie = nil;

        if (!strcmp(trackInfo->CodecID, "A_AC3")) {
            // read first header to create track
            int firstFrame = mkv_ReadFrame(_matroskaFile, 0, &rt, &StartTime, &EndTime, &FilePos, &FrameSize, &Frame, &FrameFlags, &FrameDiscard, NULL, NULL, NULL);

            if (firstFrame != 0) {
                mkv_Seek(_matroskaFile, 0, 0);
                free(Frame);
                return nil;
            }

            if (copyMkvPacket(trackInfo, &Frame, &FrameSize)) {

                // parse AC3 header
                // collect all the necessary meta information
                uint64_t fscod, frmsizecod, bsid, bsmod, acmod, lfeon;
                uint32_t lfe_offset = 4;

                fscod = (*(Frame+4) >> 6) & 0x3;
                frmsizecod = (*(Frame+4) & 0x3f) >> 1;
                bsid =  (*(Frame+5) >> 3) & 0x1f;
                bsmod = (*(Frame+5) & 0xf);
                acmod = (*(Frame+6) >> 5) & 0x7;
                if (acmod == 2) {
                    lfe_offset -= 2;
                } else {
                    if ((acmod & 1) && acmod != 1) {
                        lfe_offset -= 2;
                    }
                    if (acmod & 4) {
                        lfe_offset -= 2;
                    }
                }
                lfeon = (*(Frame+6) >> lfe_offset) & 0x1;

                NSMutableData *mutableCookie = [[NSMutableData alloc] init];
                [mutableCookie appendBytes:&fscod length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&bsid length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&bsmod length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&acmod length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&lfeon length:sizeof(uint64_t)];
                [mutableCookie appendBytes:&frmsizecod length:sizeof(uint64_t)];

                magicCookie = mutableCookie;

                free(Frame);
            }

            mkv_Seek(_matroskaFile, 0, 0);
        }

        else if (!strcmp(trackInfo->CodecID, "A_EAC3")) {
#ifdef DEBUG_PARSER
			uint16_t mkvpktnum = 0;
#endif
			struct eac3_info *context = NULL;
            SegmentInfo *segInfo = mkv_GetFileInfo(_matroskaFile);

			while (!mkv_ReadFrame(_matroskaFile, 0, &rt, &StartTime, &EndTime, &FilePos, &FrameSize, &Frame, &FrameFlags, &FrameDiscard, NULL, NULL, NULL)) {
                if (StartTime > (segInfo->Duration / 64)) {
                    free(Frame);
                    break;
                }
                if (copyMkvPacket(trackInfo, &Frame, &FrameSize)) {
#ifdef DEBUG_PARSER
					printf("\n\nMP42MkvImporter.magicCookieForTrack Analyzing MKV EAC3 packet number %d at filepos 0x%llX (%llu) with size 0x%X (%u) bits\n", mkvpktnum++, FilePos, FilePos, FrameSize * 8, FrameSize * 8);
#endif
					analyze_EAC3((void *)&context, (uint8_t *)Frame, FrameSize);
                }
                free(Frame);
            }

            if (context) {
                magicCookie = (NSData *)CFBridgingRelease(createCookie_EAC3(context));
                free(context);
            }

            mkv_Seek(_matroskaFile, 0, 0);
        }
        return magicCookie;
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

- (MP42AudioEmbeddedExtension)streamExtensionTypeForAudioTrack:(MP42AudioTrack *)track mkvTrack:(TrackInfo *)trackInfo
{
	struct eac3_info *context = NULL;
	uint8_t mkvpktnum = 0;

	if (!strcmp(trackInfo->CodecID, "A_EAC3")) {
		mkv_SetTrackMask(_matroskaFile, ~(1l << track.sourceId));
		
		uint64_t    StartTime, EndTime, FilePos;
		uint32_t    rt, FrameSize, FrameFlags;
        int64_t     FrameDiscard;
        char       *Frame = NULL;
		
		while (!mkv_ReadFrame(_matroskaFile, 0, &rt, &StartTime, &EndTime, &FilePos, &FrameSize, &Frame, &FrameFlags, &FrameDiscard, NULL, NULL, NULL)) {
            if (mkvpktnum++ > 5) {
                free(Frame);
                break;
            }
#ifdef DEBUG_PARSER
            printf("\nMP42MkvImporter.streamExtensionTypeForAudioTrack analyzing MKV EAC3 packet number %d at filepos 0x%llX (%llu) with size 0x%X (%u) bits\n", mkvpktnum++, FilePos,   FilePos, FrameSize * 8, FrameSize * 8);
#endif
            analyze_EAC3((void *)&context, (uint8_t *)Frame, FrameSize); // This routine allocates buffer for context, because we're passing NULL as input!
            free(Frame);
		}
	}

    mkv_Seek(_matroskaFile, 0, 0);

	if (context) {
        if (context->ec3_extension_type == EC3Extension_JOC) {
            track.extensionType = kMP42AudioEmbeddedExtension_JOC;
        }
        free_EAC3_context(context);
	}
	
	return track.extensionType;
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
    else if (!strcmp(trackInfo->CodecID, "A_MS/ACM")) {
        waveformatextensible_t ex;

        if (!analyze_WAVEFORMATEX(trackInfo->CodecPrivate, trackInfo->CodecPrivateSize, &ex)) {

            if (ex.Format.wFormatTag == 0xFFFE) {
                if (ex.SubFormat.Data1 == 0x0001) {
                    result.mFormatID = kAudioFormatLinearPCM;
                    result.mFormatFlags += kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
                } else if (ex.SubFormat.Data1 == 0x0003) {
                    result.mFormatID = kAudioFormatLinearPCM;
                    result.mFormatFlags += kAudioFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked;
                }
                result.mSampleRate = ex.Format.nSamplesPerSec;
                result.mBitsPerChannel = ex.Samples.wSamplesPerBlock;
            } else {
                if (ex.SubFormat.Data1 == 0x0001) {
                    result.mFormatID = kAudioFormatLinearPCM;
                    result.mFormatFlags += kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
                } else if (ex.SubFormat.Data1 == 0x0003) {
                    result.mFormatID = kAudioFormatLinearPCM;
                    result.mFormatFlags += kAudioFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked;
                }
                result.mSampleRate = ex.Format.nSamplesPerSec;
                result.mBitsPerChannel = ex.Samples.wSamplesPerBlock;
            }
        }
    }
    return result;
}

- (BOOL)supportsPreciseTimestamps {
    return YES;
}

- (BOOL)audioTrackUsesExplicitEncoderDelay:(MP42Track *)track
{
    TrackInfo *trackInfo = mkv_GetTrackInfo(_matroskaFile, track.sourceId);
    return trackInfo->CodecDelay != 0;
}

- (void)demux
{
    @autoreleasepool {

        unsigned long TrackMask = ~0;

        NSArray<MP42Track *> *inputTracks = self.inputTracks;

        NSUInteger tracksNumber = inputTracks.count;
        MatroskaDemuxHelper *helpers[self.tracks.count];

        for (NSUInteger index = 0; index < tracksNumber; index += 1) {
            MP42Track *track = inputTracks[index];

            MatroskaDemuxHelper *demuxHelper = [[MatroskaDemuxHelper alloc] init];
            demuxHelper->sourceID = track.sourceId;
            demuxHelper->trackInfo = mkv_GetTrackInfo(_matroskaFile, track.sourceId);
            demuxHelper->timescale = track.timescale;

            helpers[track.sourceId] = demuxHelper;
            [_helpers addObject:demuxHelper];

            TrackMask &= ~(1l << track.sourceId);
        }

        // mask other tracks because we don't need them
        mkv_SetTrackMask(_matroskaFile, TrackMask);

        uint64_t    StartTime, EndTime, FilePos;
        uint32_t    Track, FrameSize, FrameFlags;
        int64_t     FrameDiscard;
        char       *Frame = NULL;

        MP42SampleBuffer *frameSample = nil, *currentSample = nil;
        int64_t     duration, next_duration;

        while (!mkv_ReadFrame(_matroskaFile, 0, &Track, &StartTime, &EndTime, &FilePos, &FrameSize, &Frame, &FrameFlags, &FrameDiscard, NULL, NULL, NULL)) {

            if (self.cancelled) {
                free(Frame);
                break;
            }

            self.progress = (StartTime / _fileDuration / 10000);

            MatroskaDemuxHelper *demuxHelper = helpers[Track];
            TrackInfo *trackInfo = demuxHelper->trackInfo;

            if (StartTime < demuxHelper->startTime) {
                demuxHelper->startTime = StartTime;
            }

            if (trackInfo->Type == TT_AUDIO) {

                if (copyMkvPacket(trackInfo, &Frame, &FrameSize)) {

                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->data = Frame;
                    sample->size = FrameSize;
                    sample->timescale = demuxHelper->timescale;
                    sample->duration = MP4_INVALID_DURATION;
                    sample->decodeTimestamp = StartTime;
                    sample->flags = MP42SampleBufferFlagIsSync;
                    sample->trackId = demuxHelper->sourceID;

#define VARIABLE_AUDIO_RATE 1

#ifdef VARIABLE_AUDIO_RATE
                    double scaledStartTime = sample->decodeTimestamp * (double)mkv_TruncFloat(trackInfo->AV.Audio.SamplingFreq) / 1000000000.f;

                    if (demuxHelper->previousSample) {
                        uint64_t sampleDuration = scaledStartTime - demuxHelper->currentTime;

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
                        demuxHelper->currentTime = scaledStartTime;
                    }

                    demuxHelper->previousSample = sample;
#else
                    [self enqueue:sample];
#endif
                    demuxHelper->samplesWritten++;
                }
            }

            if (trackInfo->Type == TT_SUB) {
                if (copyMkvPacket(trackInfo, &Frame, &FrameSize)) {
                    if (strcmp(trackInfo->CodecID, "S_VOBSUB") && strcmp(trackInfo->CodecID, "S_HDMV/PGS")) {

                        MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                        sample->data = Frame;
                        sample->size = FrameSize;
                        sample->timescale = demuxHelper->timescale;
                        sample->duration = EndTime / SCALE_FACTOR - StartTime / SCALE_FACTOR;
                        sample->decodeTimestamp = StartTime / SCALE_FACTOR;
                        sample->flags = MP42SampleBufferFlagIsSync;
                        sample->trackId = demuxHelper->sourceID;

                        demuxHelper->samplesWritten++;
                        [self enqueue:sample];

                    } else {
                        MP42SampleBuffer *nextSample = [[MP42SampleBuffer alloc] init];
                        nextSample->data = Frame;
                        nextSample->size = FrameSize;
                        nextSample->timescale = demuxHelper->timescale;
                        nextSample->decodeTimestamp = StartTime;
                        nextSample->flags = MP42SampleBufferFlagIsSync;
                        nextSample->trackId = demuxHelper->sourceID;

                        // PGS are usually stored with just the start time, and blank samples to fill the gaps
                        if (!strcmp(trackInfo->CodecID, "S_HDMV/PGS")) {
                            if (!demuxHelper->previousSample) {
                                demuxHelper->previousSample = [[MP42SampleBuffer alloc] init];
                                demuxHelper->previousSample->timescale = demuxHelper->timescale;
                                demuxHelper->previousSample->duration = StartTime / SCALE_FACTOR;
                                demuxHelper->previousSample->offset = 0;
                                demuxHelper->previousSample->decodeTimestamp = StartTime;
                                demuxHelper->previousSample->flags = MP42SampleBufferFlagIsSync;
                                demuxHelper->previousSample->trackId = demuxHelper->sourceID;
                            } else {
                                if (nextSample->decodeTimestamp < demuxHelper->previousSample->decodeTimestamp) {
                                    // Out of order samples? swap the next with the previous
                                    MP42SampleBuffer *temp = nextSample;
                                    nextSample = demuxHelper->previousSample;
                                    demuxHelper->previousSample = temp;
                                }

                                demuxHelper->previousSample->duration = (nextSample->decodeTimestamp - demuxHelper->previousSample->decodeTimestamp) / SCALE_FACTOR;
                            }

                            demuxHelper->samplesWritten++;
                            [self enqueue:demuxHelper->previousSample];

                            demuxHelper->previousSample = nextSample;

                        } else if (!strcmp(trackInfo->CodecID, "S_VOBSUB")) {
                            // VobSub seems to have an end duration, and no blank samples, so create a new one each time to fill the gaps
                            if (StartTime > demuxHelper->currentTime) {
                                MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                                sample->data = calloc(1, 2);
                                sample->size = 2;
                                sample->timescale = demuxHelper->timescale;
                                sample->duration = (StartTime - demuxHelper->currentTime) / SCALE_FACTOR;
                                sample->flags = MP42SampleBufferFlagIsSync;
                                sample->trackId = demuxHelper->sourceID;

                                [self enqueue:sample];
                            }

                            nextSample->duration = (EndTime - StartTime) / SCALE_FACTOR;

                            [self enqueue:nextSample];

                            demuxHelper->currentTime = EndTime;
                        }
                    }
                }
            }

            else if (trackInfo->Type == TT_VIDEO) {

                copyMkvPacket(trackInfo, &Frame, &FrameSize);

                // read frames from file
                frameSample = [[MP42SampleBuffer alloc] init];
                frameSample->data = Frame;
                frameSample->size = FrameSize;
                frameSample->timescale = demuxHelper->timescale;
                frameSample->decodeTimestamp = StartTime;
                frameSample->presentationOutputTimestamp = EndTime;
                frameSample->flags = (FrameFlags & FRAME_KF) ? MP42SampleBufferFlagIsSync : 0;
                frameSample->trackId = demuxHelper->sourceID;
                [demuxHelper->queue addObject:frameSample];

                if (demuxHelper->queue.count < BUFFER_SIZE) {
                    continue;
                } else {
                    currentSample = [demuxHelper->queue objectAtIndex:demuxHelper->buffer];

                    // Matroska stores only the start and end time in decode order, so we need to recreate
                    // the frame duration and the offset from the start time, the end time is useless
                    // duration calculation
                    duration = demuxHelper->queue.lastObject->decodeTimestamp - currentSample->decodeTimestamp;

                    for (MP42SampleBuffer *sample in demuxHelper->queue) {
                        if (sample != currentSample && (sample->decodeTimestamp >= currentSample->decodeTimestamp)) {
                            if ((next_duration = (sample->decodeTimestamp - currentSample->decodeTimestamp)) < duration) {
                                duration = next_duration;
                            }
                        }
                    }

                    if (duration == 0) {
                        duration = 10000;
                    }

                    // offset calculation
                    int64_t offset = currentSample->decodeTimestamp / 10000.0f - demuxHelper->currentTime / 10000.0f;

                    demuxHelper->currentTime += duration;

                    currentSample->duration = duration / 10000.0f;
                    currentSample->offset = offset;

                    // save the minimum offset, used later to keep all the offset values positive
                    if (currentSample->offset < demuxHelper->minDisplayOffset) {
                        demuxHelper->minDisplayOffset = currentSample->offset;
                    }

                    if (demuxHelper->buffer >= BUFFER_SIZE) {
                        [demuxHelper->queue removeObjectAtIndex:0];
                    }
                    if (demuxHelper->buffer < BUFFER_SIZE) {
                        demuxHelper->buffer++;
                    }

                    demuxHelper->samplesWritten++;
                    [self enqueue:currentSample];
                }
            }
        }

        for (MatroskaDemuxHelper *demuxHelper in _helpers) {
            TrackInfo *trackInfo = demuxHelper->trackInfo;

            if (demuxHelper->queue) {

                while (demuxHelper->queue.count) {
                    if (demuxHelper->bufferFlush == 1) {
                        // add a last sample to get the duration for the last frame
                        MP42SampleBuffer *lastSample = demuxHelper->queue.lastObject;
                        for (MP42SampleBuffer *sample in demuxHelper->queue) {
                            if (sample->decodeTimestamp > lastSample->decodeTimestamp) {
                                lastSample = sample;
                            }
                        }
                        frameSample = [[MP42SampleBuffer alloc] init];
                        frameSample->decodeTimestamp = lastSample->presentationOutputTimestamp;
                        [demuxHelper->queue addObject:frameSample];
                    }
                    currentSample = [demuxHelper->queue objectAtIndex:demuxHelper->buffer];

                    // matroska stores only the start and end time, so we need to recreate
                    // the frame duration and the offset from the start time, the end time is useless
                    // duration calculation
                    duration = demuxHelper->queue.lastObject->decodeTimestamp - currentSample->decodeTimestamp;

                    for (MP42SampleBuffer *sample in demuxHelper->queue) {
                        if (sample != currentSample && (sample->decodeTimestamp >= currentSample->decodeTimestamp)) {
                            if ((next_duration = (sample->decodeTimestamp - currentSample->decodeTimestamp)) < duration) {
                                duration = next_duration;
                            }
                        }
                    }

                    // offset calculation
                    int64_t offset = currentSample->decodeTimestamp / 10000.0f - demuxHelper->currentTime / 10000.0f;

                    demuxHelper->currentTime += duration;

                    currentSample->duration = duration / 10000.0f;
                    currentSample->offset = offset;

                    // save the minimum offset, used later to keep the all the offset values positive
                    if (currentSample->offset < demuxHelper->minDisplayOffset) {
                        demuxHelper->minDisplayOffset = currentSample->offset;
                    }

                    if (demuxHelper->buffer >= BUFFER_SIZE) {
                        [demuxHelper->queue removeObjectAtIndex:0];
                    }

                    demuxHelper->samplesWritten++;
                    [self enqueue:currentSample];

                    demuxHelper->bufferFlush++;
                    if (demuxHelper->bufferFlush >= BUFFER_SIZE - 1) {
                        break;
                    }
                }
            }

            if (demuxHelper->previousSample) {
                if (trackInfo->Type == TT_SUB) {
                    demuxHelper->previousSample->duration = 100;
                }

                [self enqueue:demuxHelper->previousSample];
                demuxHelper->previousSample = nil;
            }
        }

        [self setDone];
    }
}

- (MatroskaDemuxHelper *)helperWithTrackID:(MP4TrackId)trackID
{
    for (MatroskaDemuxHelper *helper in _helpers) {
        if (helper->sourceID == trackID) {
            return helper;
        }
    }

    return nil;
}

- (void)cleanUp:(MP42Track *)track fileHandle:(MP4FileHandle)fileHandle
{
    MatroskaDemuxHelper *demuxHelper = [self helperWithTrackID:track.sourceId];
    MP4TrackId trackId = track.trackId;

    if (demuxHelper->minDisplayOffset != 0) {

        for (uint32_t i = 1; i <= demuxHelper->samplesWritten; i++) {
            int64_t correctedOffset = (int64_t)MP4GetSampleRenderingOffset(fileHandle, trackId, i) - demuxHelper->minDisplayOffset;
            MP4SetSampleRenderingOffset(fileHandle,
                                        trackId,
                                        i,
                                        correctedOffset);
        }

        MP4Duration editDuration = MP4ConvertFromTrackDuration(fileHandle, trackId,
                                                               MP4GetTrackDuration(fileHandle, trackId),
                                                               MP4GetTimeScale(fileHandle));

        
        // Add an empty edit list if the first pts is not 0.
        // FIXME
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
    else {
        MP4Duration editDuration = MP4ConvertFromTrackDuration(fileHandle, trackId,
                                                               MP4GetTrackDuration(fileHandle, trackId),
                                                               MP4GetTimeScale(fileHandle));

        MP4AddTrackEdit(fileHandle,
                        trackId,
                        MP4_INVALID_EDIT_ID,
                        0,
                        editDuration,
                        0);
    }
}

- (NSString *)description
{
    return @"Matroska demuxer";
}

static int readData(struct StdIoStream  *ioStream, uint64_t pos, uint8_t **data, size_t dataSize)
{
    if (fseeko(ioStream->fp, pos, SEEK_SET)) {
#ifdef DEBUG
        fprintf(stderr,"fseeko(): %s\n", strerror(errno));
#endif
        return 0;
    }

    size_t rd = fread(*data, 1, dataSize, ioStream->fp);

    if (rd != dataSize) {
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

        return 0;
    }

    return 1;
}

static int copyMkvPacket(TrackInfo *trackInfo, char **Frame, uint32_t *FrameSize)
{
    uint8_t *packet = NULL;
    uint32_t iSize = *FrameSize;

    if (trackInfo->CompMethodPrivateSize || trackInfo->CompEnabled) {
        if (trackInfo->CompMethodPrivateSize != 0) {
            packet = malloc(iSize + trackInfo->CompMethodPrivateSize);
            memcpy(packet, trackInfo->CompMethodPrivate, trackInfo->CompMethodPrivateSize);
        } else {
            packet = malloc(iSize);
        }

        if (packet == NULL) {
            fprintf(stderr,"Out of memory\n");
            free(*Frame);
            return 0;
        }

        memcpy(packet + trackInfo->CompMethodPrivateSize, *Frame, iSize);
        iSize += trackInfo->CompMethodPrivateSize;

        free(*Frame);

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

        *Frame = (char *)packet;
        *FrameSize = iSize;
        return 1;
    } else {
        return 1;
    }
}


@end
