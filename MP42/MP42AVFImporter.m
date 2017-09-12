//
//  MP42MkvFileImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import "MP42AVFImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42Languages.h"
#import "MP42File.h"
#import "MP42Image.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42FormatUtilites.h"
#import "MP42Track+Muxer.h"
#import "MP42Track+Private.h"

#import "MP42EditListsReconstructor.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AVFDemuxHelper : NSObject {
@public
    AVAssetReaderOutput *assetReaderOutput;
    MP42EditListsReconstructor *editsConstructor;
}

@end

@implementation AVFDemuxHelper

- (void)dealloc {
    [editsConstructor release];
    [super dealloc];
}

@end

@implementation MP42AVFImporter {
    AVAsset *_localAsset;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"mov", @"qt", @"mp4", @"m4v", @"m4a", @"mp3", @"m2ts", @"ts", @"mts",
             @"ac3", @"eac3", @"ec3", @"webvtt", @"vtt", @"caf", @"aif", @"aiff", @"aifc", @"wav", @"flac"];
}

- (BOOL)supportsPreciseTimestamps {
    return YES;
}

- (FourCharCode)formatForTrack:(AVAssetTrack *)track {
    FourCharCode result = 0;
    CMFormatDescriptionRef formatDescription = (CMFormatDescriptionRef)track.formatDescriptions.firstObject;

    if (formatDescription) {
        FourCharCode code = CMFormatDescriptionGetMediaSubType(formatDescription);
        switch (code) {
            case 'ms \0':
                result = kMP42AudioCodecType_AC3;
                break;
            case 'flac':
                result = kMP42AudioCodecType_FLAC;
                break;
            case 'SRT ':
                result = kMP42SubtitleCodecType_Text;
                break;
            case 'SSA ':
                result = kMP42SubtitleCodecType_SSA;
                break;
            default:
                result = code;
                break;
        }
    }
    return result;
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)outError {
    if ((self = [super initWithURL:fileURL])) {
        _localAsset = [[AVAsset assetWithURL:self.fileURL] retain];

        NSArray<AVAssetTrack *> *tracks = [_localAsset tracks];
        CMTime globaDuration = _localAsset.duration;

        NSArray *availableChapter = [_localAsset availableChapterLocales];
        MP42ChapterTrack *chapters = nil;

        // Checks if there is a chapter tracks
        if (tracks.count) {
            for (NSLocale *locale in availableChapter) {
                chapters = [[MP42ChapterTrack alloc] init];
                NSArray *chapterList = [_localAsset chapterMetadataGroupsWithTitleLocale:locale containingItemsWithCommonKeys:nil];
                for (AVTimedMetadataGroup *chapterData in chapterList) {
                    for (AVMetadataItem *item in [chapterData items]) {
                        CMTime time = [item time];
                        [chapters addChapter:[item stringValue] duration:time.value * time.timescale / 1000];
                    }
                }
            }
        }

        // Converts the tracks to the MP42File types
        for (AVAssetTrack *track in tracks) {

            MP42Track *newTrack = nil;

            // Retrieves the formatDescription
            NSArray *formatDescriptions = track.formatDescriptions;
            CMFormatDescriptionRef formatDescription = (CMFormatDescriptionRef)formatDescriptions.firstObject;

            if ([track.mediaType isEqualToString:AVMediaTypeVideo]) {

                // Video type, do the usual video things
                MP42VideoTrack *videoTrack = [[MP42VideoTrack alloc] init];
                CGSize naturalSize = track.naturalSize;

                videoTrack.trackWidth = naturalSize.width;
                videoTrack.trackHeight = naturalSize.height;

                videoTrack.width = naturalSize.width;
                videoTrack.height = naturalSize.height;
                
                videoTrack.transform = track.preferredTransform;

                if (formatDescription) {

                    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                    videoTrack.width = dimensions.width;
                    videoTrack.height = dimensions.height;

                    // Reads the pixel aspect ratio information
                    CFDictionaryRef pixelAspectRatioFromCMFormatDescription = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_PixelAspectRatio);

                    if (pixelAspectRatioFromCMFormatDescription) {
                        int hSpacing, vSpacing;
                        CFNumberGetValue(CFDictionaryGetValue(pixelAspectRatioFromCMFormatDescription, kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing), kCFNumberIntType, &hSpacing);
                        CFNumberGetValue(CFDictionaryGetValue(pixelAspectRatioFromCMFormatDescription, kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing), kCFNumberIntType, &vSpacing);
                        videoTrack.hSpacing = hSpacing;
                        videoTrack.vSpacing = vSpacing;
                    }
                    else {
                        videoTrack.hSpacing = 1;
                        videoTrack.vSpacing = 1;
                    }

                    // Reads the clean aperture information
                    CFDictionaryRef cleanApertureFromCMFormatDescription = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_CleanAperture);

                    if (cleanApertureFromCMFormatDescription) {
                        double cleanApertureWidth, cleanApertureHeight;
                        double cleanApertureHorizontalOffset, cleanApertureVerticalOffset;
                        CFNumberGetValue(CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureWidth),
                                         kCFNumberDoubleType, &cleanApertureWidth);
                        CFNumberGetValue(CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureHeight),
                                         kCFNumberDoubleType, &cleanApertureHeight);
                        CFNumberGetValue(CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureHorizontalOffset),
                                         kCFNumberDoubleType, &cleanApertureHorizontalOffset);
                        CFNumberGetValue(CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureVerticalOffset),
                                         kCFNumberDoubleType, &cleanApertureVerticalOffset);

                        videoTrack.cleanApertureWidthN = cleanApertureWidth;
                        videoTrack.cleanApertureWidthD = 1;
                        videoTrack.cleanApertureHeightN = cleanApertureHeight;
                        videoTrack.cleanApertureHeightD = 1;
                        videoTrack.horizOffN = cleanApertureHorizontalOffset;
                        videoTrack.horizOffD = 1;
                        videoTrack.vertOffN = cleanApertureVerticalOffset;
                        videoTrack.vertOffD = 1;
                    }

                    // Color
                    CFStringRef colorPrimaries = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_ColorPrimaries);

                    if (colorPrimaries) {
                        if (CFEqual(colorPrimaries, kCMFormatDescriptionColorPrimaries_ITU_R_709_2)) {
                            videoTrack.colorPrimaries = 1;
                        }
                        else if (CFEqual(colorPrimaries, kCMFormatDescriptionColorPrimaries_EBU_3213)) {
                            videoTrack.colorPrimaries = 5;
                        }
                        else if (CFEqual(colorPrimaries, kCMFormatDescriptionColorPrimaries_SMPTE_C)) {
                            videoTrack.colorPrimaries = 6;
                        }
                        else if (CFEqual(colorPrimaries, kCMFormatDescriptionColorPrimaries_ITU_R_2020)) {
                            videoTrack.colorPrimaries = 9;
                        }
                        else if (CFEqual(colorPrimaries, kCMFormatDescriptionColorPrimaries_DCI_P3)) {
                            videoTrack.colorPrimaries = 11;
                        }
                        else if (CFEqual(colorPrimaries, kCMFormatDescriptionColorPrimaries_P3_D65)) {
                            videoTrack.colorPrimaries = 12;
                        }
                        else if (CFEqual(colorPrimaries, kCMFormatDescriptionColorPrimaries_P22)) {
                            // ???
                            videoTrack.colorPrimaries = 1;
                        }
                    }

                    CFStringRef transferFunctions = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_TransferFunction);

                    if (transferFunctions) {
                        if (CFEqual(transferFunctions, kCMFormatDescriptionTransferFunction_ITU_R_709_2) ||
                            CFEqual(transferFunctions, kCMFormatDescriptionTransferFunction_ITU_R_2020)) {
                            videoTrack.transferCharacteristics = 1;
                        }
                        else if (CFEqual(transferFunctions, kCMFormatDescriptionTransferFunction_SMPTE_240M_1995)) {
                            videoTrack.transferCharacteristics = 7;
                        }
                        else if (CFEqual(transferFunctions, CFSTR("SMPTE_ST_2084_PQ"))) { // kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
                            videoTrack.transferCharacteristics = 16;
                        }
                        else if (CFEqual(transferFunctions, kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1)) {
                            videoTrack.transferCharacteristics = 17;
                        }
                        else if (CFEqual(transferFunctions, CFSTR("ITU_R_2100_HLG"))) { // kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
                            videoTrack.transferCharacteristics = 18;
                        }
                    }

                    CFStringRef YCbCrMatrix = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_YCbCrMatrix);

                    if (YCbCrMatrix) {
                        if (CFEqual(YCbCrMatrix, kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2)) {
                            videoTrack.matrixCoefficients = 1;
                        }
                        else if (CFEqual(YCbCrMatrix, kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4)) {
                            videoTrack.matrixCoefficients = 6;
                        }
                        else if (CFEqual(YCbCrMatrix, kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995)) {
                            videoTrack.matrixCoefficients = 7;
                        }
                        else if (CFEqual(YCbCrMatrix, kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)) {
                            videoTrack.matrixCoefficients = 9;
                        }
                    }
                }
                newTrack = videoTrack;

            }
            else if ([track.mediaType isEqualToString:AVMediaTypeAudio]) {

                // Audio type, check the channel layout and channels number
                MP42AudioTrack *audioTrack = [[MP42AudioTrack alloc] init];

                if (formatDescription) {
                    size_t layoutSize = 0;
                    const AudioChannelLayout *layout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, &layoutSize);

                    if (layoutSize) {
                        audioTrack.channels = AudioChannelLayoutTag_GetNumberOfChannels(layout->mChannelLayoutTag);
                        audioTrack.channelLayoutTag = layout->mChannelLayoutTag;
                    }
                    else {
                        // Guess the layout.
                        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
                        audioTrack.channels = asbd->mChannelsPerFrame;
                        audioTrack.channelLayoutTag = getDefaultChannelLayout(asbd->mChannelsPerFrame);
                    }
                }
                newTrack = audioTrack;

            }
            else if ([track.mediaType isEqualToString:AVMediaTypeSubtitle]) {

                // Subtitle type, nothing interesting here
                newTrack = [[MP42SubtitleTrack alloc] init];

            }
            else if ([track.mediaType isEqualToString:AVMediaTypeClosedCaption]) {

                // Closed caption type, nothing interesting here
                newTrack = [[MP42ClosedCaptionTrack alloc] init];

            }
            else if ([track.mediaType isEqualToString:AVMediaTypeText]) {

                FourCharCode code = 0;
                if (formatDescription) {
                    code = CMFormatDescriptionGetMediaSubType(formatDescription);
                }
                if (code == kCMSubtitleFormatType_WebVTT) {
                    newTrack = [[MP42SubtitleTrack alloc] init];
                }
                else if (chapters) {
                    // It looks like there is no way to know what text track is used for chapters in the original file.
                        newTrack = chapters;
                }
                else {
                    newTrack = [[MP42SubtitleTrack alloc] init];
                }
            }
            else {
                // Unknown type
                FourCharCode mediaType = kMP42MediaType_Unknown;
                if (formatDescription) {
                    mediaType = CMFormatDescriptionGetMediaType(formatDescription);
                }
                newTrack = [[MP42Track alloc] init];
                newTrack.mediaType = mediaType;
            }

            // Set the usual track properties
            newTrack.format = [self formatForTrack:track];
            newTrack.trackId = track.trackID;
            newTrack.URL = self.fileURL;

            // Use the global duration if track duration is not available.
            CMTimeRange timeRange = track.timeRange;
            if (timeRange.duration.timescale > 0) {
                newTrack.duration = timeRange.duration.value / timeRange.duration.timescale * 1000;
            }
            else {
                newTrack.duration = globaDuration.value / globaDuration.timescale * 1000;
            }
            newTrack.bitrate = track.estimatedDataRate;
            if (track.totalSampleDataLength > 0) {
                newTrack.dataLength = track.totalSampleDataLength;
            }
            else {
                newTrack.dataLength = newTrack.duration * newTrack.bitrate / 1000;
            }

            NSArray<AVMetadataItem *> *trackMetadata = [track metadataForFormat:AVMetadataFormatQuickTimeUserData];

            // "name" is undefined in AVMetadataFormat.h, so read the official track name "tnam", and then "name". On 10.7, "name" is returned as an NSData
            NSString *trackName = [[[AVMetadataItem metadataItemsFromArray:trackMetadata
                                                            withKey:AVMetadataQuickTimeUserDataKeyTrackName
                                                                  keySpace:nil] firstObject] stringValue];

            if (trackName.length) {
                newTrack.name = trackName;
            }
            else {
                id trackName_oldFormat = [[[AVMetadataItem metadataItemsFromArray:trackMetadata
                                                                          withKey:@"name"
                                                                         keySpace:nil] firstObject] value];

                if ([trackName_oldFormat isKindOfClass:[NSString class]]) {
                    newTrack.name = trackName_oldFormat;
                }
                else if ([trackName_oldFormat isKindOfClass:[NSData class]]) {
                    newTrack.name = [NSString stringWithCString:[trackName_oldFormat bytes]
                                                       encoding:NSMacOSRomanStringEncoding];
                }
            }

            if (track.extendedLanguageTag) {
                newTrack.language = track.extendedLanguageTag;
            }
            else if (track.languageCode) {
                newTrack.language = [MP42Languages.defaultManager extendedTagForISO_639_2:track.languageCode];
            }

            // Media characteristic tags, requires 10.10 or later
            if ([[AVMetadataItem class] respondsToSelector:@selector(metadataItemsFromArray:filteredByIdentifier:)]) {

                NSArray<AVMetadataItem *> *mediaTags = [AVMetadataItem metadataItemsFromArray:trackMetadata
                                                                     filteredByIdentifier:AVMetadataIdentifierQuickTimeUserDataTaggedCharacteristic];

                if (mediaTags.count) {
                    NSMutableSet<NSString *> *tags = [NSMutableSet set];

                    for (AVMetadataItem *tag in mediaTags) {
                        [tags addObject:tag.stringValue];
                    }
                    newTrack.mediaCharacteristicTags = tags;
                }
            }

            [self addTrack:newTrack];
            [newTrack release];
        }

        [self convertMetadata];
    }

    return self;
}

#pragma mark - Metadata

/**
 *  Converts an array of NSDictionary to a single string
 *  with the components separated by ", ".
 *
 *  @param array the array of strings.
 *
 *  @return a concatenated string.
 */
- (NSString *)stringFromArray:(NSArray<NSDictionary *> *)array key:(id)key {
    NSMutableString *result = [NSMutableString string];

    if ([array isKindOfClass:[NSArray class]]) {

        for (id name in array) {

            if (result.length) {
                [result appendString:@", "];
            }

            if ([name isKindOfClass:[NSDictionary class]]) {
                [result appendString:name[key]];
            }
            else if ([name isKindOfClass:[NSString class]]) {
                [result appendString:name];
            }
        }
    }
    else if ([array isKindOfClass:[NSString class]]) {
        NSString *name = (NSString *)array;
        [result appendString:name];
    }

    return [[result copy] autorelease];
}

- (MP42MetadataItem *)metadataItemWithValue:(id)value identifier:(NSString *)identifier
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeUnspecified
                                                      extendedLanguageTag:nil];
    return item;
}

/**
 *  Converts the AVAsset metadata to the MP42Metadata format
 */
- (void)convertMetadata {
    NSDictionary *commonItemsDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                     MP42MetadataKeyName,           AVMetadataCommonKeyTitle,
                                     //nil                          AVMetadataCommonKeyCreator,
                                     //nil,                         AVMetadataCommonKeySubject,
                                     MP42MetadataKeyDescription,    AVMetadataCommonKeyDescription,
                                     MP42MetadataKeyPublisher,      AVMetadataCommonKeyPublisher,
                                     //nil                          AVMetadataCommonKeyContributor,
                                     MP42MetadataKeyReleaseDate,    AVMetadataCommonKeyCreationDate,
                                     //nil,                         AVMetadataCommonKeyLastModifiedDate,
                                     MP42MetadataKeyUserGenre,      AVMetadataCommonKeyType,
                                     //nil,                         AVMetadataCommonKeyFormat,
                                     //nil,                         AVMetadataCommonKeyIdentifier,
                                     //nil,                         AVMetadataCommonKeySource,
                                     //nil,                         AVMetadataCommonKeyLanguage,
                                     //nil,                         AVMetadataCommonKeyRelation,
                                     //nil                          AVMetadataCommonKeyLocation,
                                     MP42MetadataKeyCopyright,      AVMetadataCommonKeyCopyrights,
                                     MP42MetadataKeyAlbum,          AVMetadataCommonKeyAlbumName,
                                     //nil,                         AVMetadataCommonKeyAuthor,
                                     //nil,                         AVMetadataCommonKeyArtwork
                                     MP42MetadataKeyArtist,         AVMetadataCommonKeyArtist,
                                     //nil,                         AVMetadataCommonKeyMake,
                                     //nil,                         AVMetadataCommonKeyModel,
                                     MP42MetadataKeyEncodingTool,   AVMetadataCommonKeySoftware,
                                     nil];

    self.metadata = [[[MP42Metadata alloc] init] autorelease];

    for (NSString *commonKey in commonItemsDict.allKeys) {
        NSArray<AVMetadataItem *> *items = [AVMetadataItem metadataItemsFromArray:_localAsset.commonMetadata
                                                                          withKey:commonKey
                                                                         keySpace:AVMetadataKeySpaceCommon];
        if (items.count) {
            [self.metadata addMetadataItem:[self metadataItemWithValue:items.lastObject.value identifier:commonItemsDict[commonKey]]];
        }
    }

    // Copy the artowrks
    NSArray<AVMetadataItem *> *items = [AVMetadataItem metadataItemsFromArray:_localAsset.commonMetadata
                                                                      withKey:AVMetadataCommonKeyArtwork
                                                                     keySpace:AVMetadataKeySpaceCommon];

    for (AVMetadataItem *item in items) {
        NSData *artworkData = item.dataValue;

        if ([artworkData isKindOfClass:[NSData class]]) {
            NSImage *imageData = [[NSImage alloc] initWithData:artworkData];
            MP42Image *image = [[MP42Image alloc] initWithImage:imageData];
            [self.metadata addMetadataItem:[self metadataItemWithValue:image identifier:MP42MetadataKeyCoverArt]];
            [image release];
            [imageData release];
        }
    }

    NSArray<NSString *> *availableMetadataFormats = [_localAsset availableMetadataFormats];

    if ([availableMetadataFormats containsObject:AVMetadataFormatiTunesMetadata]) {
        NSArray<AVMetadataItem *> *itunesMetadata = [_localAsset metadataForFormat:AVMetadataFormatiTunesMetadata];
        
        NSDictionary *itunesMetadataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                            MP42MetadataKeyAlbum,               AVMetadataiTunesMetadataKeyAlbum,
                                            MP42MetadataKeyArtist,              AVMetadataiTunesMetadataKeyArtist,
                                            MP42MetadataKeyUserComment,         AVMetadataiTunesMetadataKeyUserComment,
                                            //AVMetadataiTunesMetadataKeyCoverArt,
                                            MP42MetadataKeyCopyright,           AVMetadataiTunesMetadataKeyCopyright,
                                            MP42MetadataKeyReleaseDate,         AVMetadataiTunesMetadataKeyReleaseDate,
                                            MP42MetadataKeyEncodedBy,           AVMetadataiTunesMetadataKeyEncodedBy,
                                            //MP42MetadataKeyUserGenre,         AVMetadataiTunesMetadataKeyPredefinedGenre,
                                            MP42MetadataKeyUserGenre,           AVMetadataiTunesMetadataKeyUserGenre,
                                            MP42MetadataKeyName,                AVMetadataiTunesMetadataKeySongName,
                                            MP42MetadataKeyTrackSubTitle,       AVMetadataiTunesMetadataKeyTrackSubTitle,
                                            MP42MetadataKeyEncodingTool,        AVMetadataiTunesMetadataKeyEncodingTool,
                                            MP42MetadataKeyComposer,            AVMetadataiTunesMetadataKeyComposer,
                                            MP42MetadataKeyAlbumArtist,         AVMetadataiTunesMetadataKeyAlbumArtist,
                                            MP42MetadataKeyAccountKind,         AVMetadataiTunesMetadataKeyAccountKind,
                                            MP42MetadataKeyAccountCountry,      @"sfID",
                                            MP42MetadataKeyAppleID,             AVMetadataiTunesMetadataKeyAppleID,
                                            MP42MetadataKeyArtistID,            AVMetadataiTunesMetadataKeyArtistID,
                                            MP42MetadataKeyContentID,           AVMetadataiTunesMetadataKeySongID,
                                            MP42MetadataKeyDiscCompilation,     AVMetadataiTunesMetadataKeyDiscCompilation,
                                            MP42MetadataKeyDiscNumber,          AVMetadataiTunesMetadataKeyDiscNumber,
                                            MP42MetadataKeyGenreID,             AVMetadataiTunesMetadataKeyGenreID,
                                            MP42MetadataKeyGrouping,            AVMetadataiTunesMetadataKeyGrouping,
                                            MP42MetadataKeyPlaylistID,          AVMetadataiTunesMetadataKeyPlaylistID,
                                            MP42MetadataKeyXID,                 @"xid ",
                                            MP42MetadataKeyContentRating,       AVMetadataiTunesMetadataKeyContentRating,
                                            MP42MetadataKeyRating,              @"com.apple.iTunes.iTunEXTC",
                                            MP42MetadataKeyBeatsPerMin,         AVMetadataiTunesMetadataKeyBeatsPerMin,
                                            MP42MetadataKeyTrackNumber,         AVMetadataiTunesMetadataKeyTrackNumber,
                                            MP42MetadataKeyArtDirector,         AVMetadataiTunesMetadataKeyArtDirector,
                                            MP42MetadataKeyArranger,            AVMetadataiTunesMetadataKeyArranger,
                                            MP42MetadataKeyAuthor,              AVMetadataiTunesMetadataKeyAuthor,
                                            MP42MetadataKeyLyrics,              AVMetadataiTunesMetadataKeyLyrics,
                                            MP42MetadataKeyAcknowledgement,     AVMetadataiTunesMetadataKeyAcknowledgement,
                                            MP42MetadataKeyConductor,           AVMetadataiTunesMetadataKeyConductor,
                                            MP42MetadataKeySongDescription,     AVMetadataiTunesMetadataKeyDescription,
                                            MP42MetadataKeyDescription,         @"desc",
                                            MP42MetadataKeyLongDescription,     @"ldes",
                                            MP42MetadataKeySeriesDescription,   @"sdes",
                                            MP42MetadataKeyMediaKind,           @"stik",
                                            MP42MetadataKeyTVShow,              @"tvsh",
                                            MP42MetadataKeyTVEpisodeNumber,     @"tves",
                                            MP42MetadataKeyTVNetwork,           @"tvnn",
                                            MP42MetadataKeyTVEpisodeID,         @"tven",
                                            MP42MetadataKeyTVSeason,            @"tvsn",
                                            MP42MetadataKeyHDVideo,             @"hdvd",
                                            MP42MetadataKeyGapless,             @"pgap",
                                            MP42MetadataKeySortName,            @"sonm",
                                            MP42MetadataKeySortArtist,          @"soar",
                                            MP42MetadataKeySortAlbumArtist,     @"soaa",
                                            MP42MetadataKeySortAlbum,           @"soal",
                                            MP42MetadataKeySortComposer,        @"soco",
                                            MP42MetadataKeySortTVShow,          @"sosn",
                                            MP42MetadataKeyCategory,            @"catg",
                                            MP42MetadataKeyiTunesU,             @"itnu",
                                            MP42MetadataKeyPurchasedDate,       @"purd",
                                            MP42MetadataKeyDirector,            AVMetadataiTunesMetadataKeyDirector,
                                            //AVMetadataiTunesMetadataKeyEQ,
                                            MP42MetadataKeyLinerNotes,          AVMetadataiTunesMetadataKeyLinerNotes,
                                            MP42MetadataKeyRecordCompany,       AVMetadataiTunesMetadataKeyRecordCompany,
                                            MP42MetadataKeyOriginalArtist,      AVMetadataiTunesMetadataKeyOriginalArtist,
                                            MP42MetadataKeyPhonogramRights,     AVMetadataiTunesMetadataKeyPhonogramRights,
                                            MP42MetadataKeySongProducer,        AVMetadataiTunesMetadataKeyProducer,
                                            MP42MetadataKeyPerformer,           AVMetadataiTunesMetadataKeyPerformer,
                                            MP42MetadataKeyPublisher,           AVMetadataiTunesMetadataKeyPublisher,
                                            MP42MetadataKeySoundEngineer,       AVMetadataiTunesMetadataKeySoundEngineer,
                                            MP42MetadataKeySoloist,             AVMetadataiTunesMetadataKeySoloist,
                                            MP42MetadataKeyCredits,             AVMetadataiTunesMetadataKeyCredits,
                                            MP42MetadataKeyThanks,              AVMetadataiTunesMetadataKeyThanks,
                                            MP42MetadataKeyOnlineExtras,        AVMetadataiTunesMetadataKeyOnlineExtras,
                                            MP42MetadataKeyExecProducer,        AVMetadataiTunesMetadataKeyExecProducer,
                                            nil];

        for (NSString *itunesKey in itunesMetadataDict.allKeys) {
            items = [AVMetadataItem metadataItemsFromArray:itunesMetadata withKey:itunesKey keySpace:nil];
            if (items.count) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:items.lastObject.value identifier:itunesMetadataDict[itunesKey]]];
            }
        }

        // iTunMovi is a property list that contains more metadata, for some weird reasons.
        AVMetadataItem *iTunMovi = [[AVMetadataItem metadataItemsFromArray:itunesMetadata withKey:@"com.apple.iTunes.iTunMOVI" keySpace:nil] firstObject];

        if (iTunMovi) {
            NSData *data = [iTunMovi.stringValue dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *dma = (NSDictionary *)[NSPropertyListSerialization propertyListWithData:data
                                                                                          options:NSPropertyListImmutable
                                                                                           format:nil error:NULL];
            NSString *value;
            if ([value = [self stringFromArray:dma[@"cast"] key:@"name"] length]) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:value identifier:MP42MetadataKeyCast]];
            }

            if ([value = [self stringFromArray:dma[@"directors"] key:@"name"] length]) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:value identifier:MP42MetadataKeyDirector]];
            }

            if ([value = [self stringFromArray:dma[@"codirectors"] key:@"name"] length]) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:value identifier:MP42MetadataKeyCodirector]];
            }

            if ([value = [self stringFromArray:dma[@"producers"] key:@"name"] length]) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:value identifier:MP42MetadataKeyProducer]];
            }

            if ([value = [self stringFromArray:dma[@"screenwriters"] key:@"name"] length]) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:value identifier:MP42MetadataKeyScreenwriters]];
            }

            if ([value = dma[@"studio"] length]) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:value identifier:MP42MetadataKeyStudio]];
            }
        }
    }

    if ([availableMetadataFormats containsObject:AVMetadataFormatQuickTimeMetadata]) {
        NSArray<AVMetadataItem *> *quicktimeMetadata = [_localAsset metadataForFormat:AVMetadataFormatQuickTimeMetadata];
        
        NSDictionary *quicktimeMetadataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                               MP42MetadataKeyArtist,           AVMetadataQuickTimeMetadataKeyAuthor,
                                               MP42MetadataKeyUserComment,      AVMetadataQuickTimeMetadataKeyComment,
                                               MP42MetadataKeyCopyright,        AVMetadataQuickTimeMetadataKeyCopyright,
                                               MP42MetadataKeyReleaseDate,      AVMetadataQuickTimeMetadataKeyCreationDate,
                                               MP42MetadataKeyDirector,         AVMetadataQuickTimeMetadataKeyDirector,
                                               MP42MetadataKeyName,             AVMetadataQuickTimeMetadataKeyDisplayName,
                                               MP42MetadataKeyDescription,      AVMetadataQuickTimeMetadataKeyInformation,
                                               MP42MetadataKeyKeywords,         AVMetadataQuickTimeMetadataKeyKeywords,
                                               MP42MetadataKeySongProducer,     AVMetadataQuickTimeMetadataKeyProducer,
                                               MP42MetadataKeyPublisher,        AVMetadataQuickTimeMetadataKeyPublisher,
                                               MP42MetadataKeyAlbum,            AVMetadataQuickTimeMetadataKeyAlbum,
                                               MP42MetadataKeyArtist,           AVMetadataQuickTimeMetadataKeyArtist,
                                               MP42MetadataKeyDescription,      AVMetadataQuickTimeMetadataKeyDescription,
                                               MP42MetadataKeyEncodingTool,     AVMetadataQuickTimeMetadataKeySoftware,
                                               MP42MetadataKeyUserGenre,        AVMetadataQuickTimeMetadataKeyGenre,
                                               //AVMetadataQuickTimeMetadataKeyiXML,
                                               MP42MetadataKeyArranger,         AVMetadataQuickTimeMetadataKeyArranger,
                                               MP42MetadataKeyEncodedBy,        AVMetadataQuickTimeMetadataKeyEncodedBy,
                                               MP42MetadataKeyOriginalArtist,   AVMetadataQuickTimeMetadataKeyOriginalArtist,
                                               MP42MetadataKeyPerformer,        AVMetadataQuickTimeMetadataKeyPerformer,
                                               MP42MetadataKeyComposer,         AVMetadataQuickTimeMetadataKeyComposer,
                                               MP42MetadataKeyCredits,          AVMetadataQuickTimeMetadataKeyCredits,
                                               MP42MetadataKeyPhonogramRights,  AVMetadataQuickTimeMetadataKeyPhonogramRights,
                                               MP42MetadataKeyName,             AVMetadataQuickTimeMetadataKeyTitle, nil];
        
        for (NSString *qtKey in quicktimeMetadataDict.allKeys) {
            items = [AVMetadataItem metadataItemsFromArray:quicktimeMetadata withKey:qtKey keySpace:AVMetadataKeySpaceQuickTimeUserData];
            if (items.count) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:items.lastObject.value identifier:quicktimeMetadataDict[qtKey]]];
            }
        }
    }

    if ([availableMetadataFormats containsObject:AVMetadataFormatQuickTimeUserData]) {
        NSArray<AVMetadataItem *> *quicktimeUserDataMetadata = [_localAsset metadataForFormat:AVMetadataFormatQuickTimeUserData];
        
        NSDictionary *quicktimeUserDataMetadataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                                       MP42MetadataKeyAlbum,                AVMetadataQuickTimeUserDataKeyAlbum,
                                                       MP42MetadataKeyArranger,             AVMetadataQuickTimeUserDataKeyArranger,
                                                       MP42MetadataKeyArtist,               AVMetadataQuickTimeUserDataKeyArtist,
                                                       MP42MetadataKeyAuthor,               AVMetadataQuickTimeUserDataKeyAuthor,
                                                       MP42MetadataKeyUserComment,          AVMetadataQuickTimeUserDataKeyComment,
                                                       MP42MetadataKeyComposer,             AVMetadataQuickTimeUserDataKeyComposer,
                                                       MP42MetadataKeyCopyright,            AVMetadataQuickTimeUserDataKeyCopyright,
                                                       MP42MetadataKeyReleaseDate,          AVMetadataQuickTimeUserDataKeyCreationDate,
                                                       MP42MetadataKeyDescription,          AVMetadataQuickTimeUserDataKeyDescription,
                                                       MP42MetadataKeyDirector,             AVMetadataQuickTimeUserDataKeyDirector,
                                                       MP42MetadataKeyEncodedBy,            AVMetadataQuickTimeUserDataKeyEncodedBy,
                                                       MP42MetadataKeyName,                 AVMetadataQuickTimeUserDataKeyFullName,
                                                       MP42MetadataKeyUserGenre,            AVMetadataQuickTimeUserDataKeyGenre,
                                                       MP42MetadataKeyKeywords,             AVMetadataQuickTimeUserDataKeyKeywords,
                                                       MP42MetadataKeyOriginalArtist,       AVMetadataQuickTimeUserDataKeyOriginalArtist,
                                                       MP42MetadataKeyPerformer,            AVMetadataQuickTimeUserDataKeyPerformers,
                                                       MP42MetadataKeySongProducer,         AVMetadataQuickTimeUserDataKeyProducer,
                                                       MP42MetadataKeyPublisher,            AVMetadataQuickTimeUserDataKeyPublisher,
                                                       MP42MetadataKeyOnlineExtras,         AVMetadataQuickTimeUserDataKeyURLLink,
                                                       MP42MetadataKeyCredits,              AVMetadataQuickTimeUserDataKeyCredits,
                                                       MP42MetadataKeyPhonogramRights,      AVMetadataQuickTimeUserDataKeyPhonogramRights, nil];

        for (NSString *qtUserDataKey in quicktimeUserDataMetadataDict.allKeys) {
            items = [AVMetadataItem metadataItemsFromArray:quicktimeUserDataMetadata withKey:qtUserDataKey keySpace:AVMetadataKeySpaceQuickTimeUserData];
            if (items.count) {
                [self.metadata addMetadataItem:[self metadataItemWithValue:items.lastObject.value identifier:quicktimeUserDataMetadataDict[qtUserDataKey]]];
            }
        }
    }
}

- (NSUInteger)timescaleForTrack:(MP42Track *)track {
    AVAssetTrack *assetTrack = [_localAsset trackWithTrackID:track.sourceId];

    // Prefer the asbd sample rate, naturalTimeScale might not be
    // the right one if we are reading for .ts
    if ([assetTrack.mediaType isEqualToString:AVMediaTypeAudio] && assetTrack.naturalTimeScale == 90000) {
        CMFormatDescriptionRef formatDescription = (CMFormatDescriptionRef)assetTrack.formatDescriptions.firstObject;

        if (formatDescription) {
            const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
            return asbd->mSampleRate;
        }
    }
    return assetTrack.naturalTimeScale;
}

- (NSSize)sizeForTrack:(MP42Track *)track {
    if ([track isKindOfClass:[MP42VideoTrack class]]) {
        MP42VideoTrack *currentTrack = (MP42VideoTrack *)track;
        return NSMakeSize(currentTrack.width, currentTrack.height);
    } else {
        return NSMakeSize(0, 0);
    }
}

- (NSData *)magicCookieForTrack:(MP42Track *)track {

    AVAssetTrack *assetTrack = [_localAsset trackWithTrackID:track.sourceId];
    CMFormatDescriptionRef formatDescription = (CMFormatDescriptionRef)assetTrack.formatDescriptions.firstObject;

    if (formatDescription) {

        FourCharCode code = CMFormatDescriptionGetMediaSubType(formatDescription);

        if ([assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) {

            CFDictionaryRef extentions = CMFormatDescriptionGetExtensions(formatDescription);
            CFDictionaryRef atoms = CFDictionaryGetValue(extentions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
            CFDataRef magicCookie = NULL;

            if (code == kCMVideoCodecType_H264) {
                magicCookie = CFDictionaryGetValue(atoms, @"avcC");
            }
            else if (code == kCMVideoCodecType_HEVC || code == 'hev1') {
                magicCookie = CFDictionaryGetValue(atoms, @"hvcC");
            }
            else if (code == kCMVideoCodecType_MPEG4Video) {
                magicCookie = CFDictionaryGetValue(atoms, @"esds");
            }

            return (NSData *)magicCookie;

        } else if ([assetTrack.mediaType isEqualToString:AVMediaTypeAudio]) {

            size_t cookieSizeOut;
            const void *cookieBuffer = CMAudioFormatDescriptionGetMagicCookie(formatDescription, &cookieSizeOut);

            if (code == kAudioFormatMPEG4AAC || code == kAudioFormatMPEG4AAC_HE || code == kAudioFormatMPEG4AAC_HE_V2) {

                // Extract DecoderSpecific info
                UInt8 *buffer;
                int size;
                ReadESDSDescExt((void *)cookieBuffer, &buffer, &size, 0);

                NSData *magicCookie = [NSData dataWithBytes:buffer length:size];
                free(buffer);
                return magicCookie;

            }

            else if (code == kAudioFormatAppleLossless) {

                if (cookieSizeOut > 48) {
                    // Remove unneeded parts of the cookie, as described in ALACMagicCookieDescription.txt
                    cookieBuffer += 24;
                    cookieSizeOut = cookieSizeOut - 24 - 8;
                }

                return [NSData dataWithBytes:cookieBuffer length:cookieSizeOut];
            }

            else if (code == 'opus') {
                // dec3 atom
                // remove the atom header
                //cookieBuffer += 9;
                //cookieSizeOut = cookieSizeOut - 9;

                UInt32 *cookie = (UInt32 *)cookieBuffer;

                for (size_t i = 0; i < cookieSizeOut / 8; i++) {
                    cookie[i] = EndianS32_BtoN(cookie[i]);
                }

                return [NSData dataWithBytes:cookieBuffer length:cookieSizeOut];
            }

            else if (code == 'flac') {

                UInt32 *cookie = (UInt32 *)cookieBuffer;

                for (size_t i = 0; i < cookieSizeOut / 8; i++) {
                    cookie[i] = EndianS32_BtoN(cookie[i]);
                }

                return [NSData dataWithBytes:cookieBuffer length:cookieSizeOut];
                
            }

            else if (code == kAudioFormatEnhancedAC3) {
                // dec3 atom
                // remove the atom header
                cookieBuffer += 8;
                cookieSizeOut = cookieSizeOut - 8;

                return [NSData dataWithBytes:cookieBuffer length:cookieSizeOut];
            }

            else if (code == kAudioFormatAC3 ||
                     code == 'ms \0') {

                OSStatus err = noErr;
                size_t channelLayoutSize = 0;
                const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
                const AudioChannelLayout *channelLayout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, &channelLayoutSize);

                UInt32 bitmapSize = sizeof(UInt32);
                UInt32 channelBitmap;
                err = AudioFormatGetProperty(kAudioFormatProperty_BitmapForLayoutTag,
                                               sizeof(AudioChannelLayoutTag), &channelLayout->mChannelLayoutTag,
                                               &bitmapSize, &channelBitmap);
                if (err && AudioChannelLayoutTag_GetNumberOfChannels(channelLayout->mChannelLayoutTag) == 6) {
                    channelBitmap = 0x3F;
                }

                uint64_t fscod = 0;
                uint64_t bsid = 8;
                uint64_t bsmod = 0;
                uint64_t acmod = 7;
                uint64_t lfeon = (channelBitmap & kAudioChannelBit_LFEScreen) ? 1 : 0;
                uint64_t bit_rate_code = 15;

                switch (AudioChannelLayoutTag_GetNumberOfChannels(channelLayout->mChannelLayoutTag) - lfeon) {
                    case 1:
                        acmod = 1;
                        break;
                    case 2:
                        acmod = 2;
                        break;
                    case 3:
                        if (channelBitmap & kAudioChannelBit_CenterSurround) acmod = 3;
                        else acmod = 4;
                        break;
                    case 4:
                        if (channelBitmap & kAudioChannelBit_CenterSurround) acmod = 5;
                        else acmod = 6;
                        break;
                    case 5:
                        acmod = 7;
                        break;
                    default:
                        break;
                }

                if (asbd->mSampleRate == 48000) fscod = 0;
                else if (asbd->mSampleRate == 44100) fscod = 1;
                else if (asbd->mSampleRate == 32000) fscod = 2;
                else fscod = 3;

                NSMutableData *ac3Info = [[NSMutableData alloc] init];
                [ac3Info appendBytes:&fscod length:sizeof(uint64_t)];
                [ac3Info appendBytes:&bsid length:sizeof(uint64_t)];
                [ac3Info appendBytes:&bsmod length:sizeof(uint64_t)];
                [ac3Info appendBytes:&acmod length:sizeof(uint64_t)];
                [ac3Info appendBytes:&lfeon length:sizeof(uint64_t)];
                [ac3Info appendBytes:&bit_rate_code length:sizeof(uint64_t)];

                return [ac3Info autorelease];

            } else if (cookieSizeOut) {
                return [NSData dataWithBytes:cookieBuffer length:cookieSizeOut];
            }
        }

        else if ([assetTrack.mediaType isEqualToString:AVMediaTypeText]) {

            if (code == kCMSubtitleFormatType_WebVTT) {

                CFDictionaryRef extentions = CMFormatDescriptionGetExtensions(formatDescription);
                CFDictionaryRef atoms = CFDictionaryGetValue(extentions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
                CFDataRef magicCookie = NULL;

                magicCookie = CFDictionaryGetValue(atoms, @"vttC");

                return (NSData *)magicCookie;
            }
        }

    }
    return nil;
}

- (AudioStreamBasicDescription)audioDescriptionForTrack:(MP42AudioTrack *)track
{
    AudioStreamBasicDescription result;
    bzero(&result, sizeof(AudioStreamBasicDescription));

    AVAssetTrack *assetTrack = [_localAsset trackWithTrackID:track.sourceId];
    CMFormatDescriptionRef formatDescription = (CMFormatDescriptionRef)assetTrack.formatDescriptions.firstObject;

    if (formatDescription) {
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
        memcpy(&result, asbd, sizeof(AudioStreamBasicDescription));
    }

    return result;
}

- (BOOL)audioTrackUsesExplicitEncoderDelay:(MP42Track *)track;
{
    return YES;
}

- (void)demux {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	BOOL success = YES;
    OSStatus err = noErr;

    uint64_t currentDataLength = 0;
    uint64_t totalDataLength = 0;

    AVFDemuxHelper *demuxHelper = nil;
    NSError *localError;
    AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:_localAsset error:&localError];

	success = (assetReader != nil);
	if (success) {
        for (MP42Track *track in self.inputTracks) {
            AVAssetReaderOutput *assetReaderOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[_localAsset trackWithTrackID:track.sourceId]
                                                                                                outputSettings:nil];
            if (![assetReader canAddOutput:assetReaderOutput]) {
                NSLog(@"Unable to add the output to assetReader!");
            }

            [assetReader addOutput:assetReaderOutput];

            track.muxer_helper->demuxer_context = [[AVFDemuxHelper alloc] init];
            demuxHelper = track.muxer_helper->demuxer_context;
            demuxHelper->assetReaderOutput = assetReaderOutput;
            demuxHelper->editsConstructor = [[MP42EditListsReconstructor alloc] init];

            totalDataLength += track.dataLength;
        }
    }

    success = [assetReader startReading];

    if (!success) {
		localError = [assetReader error];
    }

    for (MP42Track *track in self.inputTracks) {
        demuxHelper = track.muxer_helper->demuxer_context;
        AVAssetReaderOutput *assetReaderOutput = demuxHelper->assetReaderOutput;

        while (!self.isCancelled) {

            CMSampleBufferRef sampleBuffer = [assetReaderOutput copyNextSampleBuffer];
            CMTimeScale timescale = [self timescaleForTrack:track];

            if (sampleBuffer) {

                CMItemCount samplesNum = CMSampleBufferGetNumSamples(sampleBuffer);

                CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
                CMTime decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
                CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                CMTime presentationOutputTimeStamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);

                CMTime currentOutputTimeStamp = CMTimeConvertScale(presentationOutputTimeStamp, timescale, kCMTimeRoundingMethod_Default);

                // Read sample attachment, to mark the frame as sync
                BOOL sync = 1;
                BOOL doNotDisplay = NO;
                CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, NO);
                if (attachmentsArray) {
                    for (NSDictionary *dict in (NSArray *)attachmentsArray) {
                        if ([dict valueForKey:(NSString *)kCMSampleAttachmentKey_NotSync]) {
                            sync = 0;
                        }
                        if ([dict valueForKey:(NSString *)kCMSampleAttachmentKey_DoNotDisplay]) {
                            doNotDisplay = YES;
                        }
                    }
                }

                CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(NULL, sampleBuffer, kCMAttachmentMode_ShouldPropagate);

                // Get CMBlockBufferRef to extract the actual data later
                CMBlockBufferRef buffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                size_t bufferSize = CMBlockBufferGetDataLength(buffer);

                // We have only a sample
                // or the format is PCM, if so send only a single buffer to improve performance
                if (samplesNum == 1 || (samplesNum > 1 && track.format == kMP42AudioCodecType_LinearPCM)) {

                    void *sampleData = malloc(bufferSize);
                    CMBlockBufferCopyDataBytes(buffer, 0, bufferSize, sampleData);

                    // Enqueues the new sample
                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->data = sampleData;
                    sample->size = bufferSize;
                    sample->duration = duration.value;
                    sample->offset = -decodeTimeStamp.value + presentationTimeStamp.value;
                    sample->decodeTimestamp = decodeTimeStamp.value;
                    sample->presentationTimestamp = presentationTimeStamp.value;
                    sample->presentationOutputTimestamp = currentOutputTimeStamp.value;
                    sample->timescale = timescale;
                    sample->flags |= sync ? MP42SampleBufferFlagIsSync : 0;
                    sample->flags |= doNotDisplay ? MP42SampleBufferFlagDoNotDisplay : 0;
                    sample->trackId = track.sourceId;
                    sample->attachments = (void *)attachments;

                    [demuxHelper->editsConstructor addSample:sample];
                    [self enqueue:sample];
                    [sample release];

                    currentDataLength += bufferSize;
                }
                // The CMSampleBufferRef contains more than one sample
                else if (samplesNum > 1) {
                    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
                        CMSampleBufferMakeDataReady(sampleBuffer);
                    }

                    // A CMSampleBufferRef can contains an multiple samples, check how many needs to be divided to separated MP42SampleBuffers
                    // First get the array with the timings for each sample
                    CMItemCount timingArrayEntries = 0;
                    CMItemCount timingArrayEntriesNeededOut = 0;
                    err = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, timingArrayEntries, NULL, &timingArrayEntriesNeededOut);
                    if (err) {
                        CFRelease(sampleBuffer);
                        continue;
                    }

                    CMSampleTimingInfo *timingArrayOut = malloc(sizeof(CMSampleTimingInfo) * timingArrayEntriesNeededOut);
                    timingArrayEntries = timingArrayEntriesNeededOut;
                    err = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, timingArrayEntries, timingArrayOut, &timingArrayEntriesNeededOut);
                    if (err) {
                        free(timingArrayOut);
                        CFRelease(sampleBuffer);
                        continue;
                    }

                    // Then the array with the size of each sample
                    CMItemCount sizeArrayEntries = 0;
                    CMItemCount sizeArrayEntriesNeededOut = 0;
                    err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, NULL, &sizeArrayEntriesNeededOut);
                    if (err) {
                        free(timingArrayOut);
                        CFRelease(sampleBuffer);
                        continue;
                    }

                    size_t *sizeArrayOut = malloc(sizeof(size_t) * sizeArrayEntriesNeededOut);
                    sizeArrayEntries = sizeArrayEntriesNeededOut;
                    err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, sizeArrayOut, &sizeArrayEntriesNeededOut);
                    if (err) {
                        free(timingArrayOut);
                        free(sizeArrayOut);
                        CFRelease(sampleBuffer);
                        continue;
                    }

                    for (uint64_t i = 0, pos = 0; i < samplesNum; i++) {
                        CMSampleTimingInfo sampleTimingInfo;
                        CMTime decodeTimeStamp;
                        CMTime presentationTimeStamp;

                        size_t sampleSize;

                        // If the size of sample timing array is equal to 1, it means every sample has got the same timing
                        if (timingArrayEntries == 1) {
                            sampleTimingInfo = timingArrayOut[0];
                            decodeTimeStamp = sampleTimingInfo.decodeTimeStamp;
                            decodeTimeStamp.value = decodeTimeStamp.value + ( sampleTimingInfo.duration.value * i);

                            presentationTimeStamp = sampleTimingInfo.presentationTimeStamp;
                            presentationTimeStamp.value = presentationTimeStamp.value + ( sampleTimingInfo.duration.value * i);
                        } else {
                            sampleTimingInfo = timingArrayOut[i];
                            decodeTimeStamp = sampleTimingInfo.decodeTimeStamp;
                            presentationTimeStamp = sampleTimingInfo.presentationTimeStamp;
                        }

                        // If the size of sample size array is equal to 1, it means every sample has got the same size
                        if (sizeArrayEntries ==  1) {
                            sampleSize = sizeArrayOut[0];
                        } else {
                            sampleSize = sizeArrayOut[i];
                        }

                        if (!sampleSize) {
                            continue;
                        }

                        void *sampleData = malloc(sampleSize);

                        if (pos < bufferSize) {
                            CMBlockBufferCopyDataBytes(buffer, pos, sampleSize, sampleData);
                            pos += sampleSize;
                        }

                        // Enqueues the new sample
                        MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];

                        if (attachments && i == 0 && CFDictionaryContainsKey(attachments, kCMSampleBufferAttachmentKey_TrimDurationAtStart)) {
                            CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 2, attachments);
                            CFDictionaryRemoveValue(copy, kCMSampleBufferAttachmentKey_TrimDurationAtEnd);
                            sample->attachments = (void *)copy;
                            CFDictionaryRef trimStart = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtStart);
                            CMTime trimStartTime = CMTimeMakeFromDictionary(trimStart);
                            trimStartTime = CMTimeConvertScale(trimStartTime, sampleTimingInfo.duration.value, kCMTimeRoundingMethod_Default);
                            currentOutputTimeStamp.value -= trimStartTime.value;

                        }

                        sample->data = sampleData;
                        sample->size = sampleSize;
                        sample->duration = sampleTimingInfo.duration.value;
                        sample->offset = -decodeTimeStamp.value + presentationTimeStamp.value;
                        sample->presentationTimestamp = presentationTimeStamp.value;
                        sample->presentationOutputTimestamp = currentOutputTimeStamp.value;
                        sample->timescale = timescale;
                        sample->flags |= sync ? MP42SampleBufferFlagIsSync : 0;
                        sample->flags |= doNotDisplay ? MP42SampleBufferFlagDoNotDisplay : 0;
                        sample->trackId = track.sourceId;

                        if (attachments && i == (samplesNum - 1) && CFDictionaryContainsKey(attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd)) {
                            CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 2, attachments);
                            CFDictionaryRemoveValue(copy, kCMSampleBufferAttachmentKey_TrimDurationAtStart);
                            sample->attachments = (void *)copy;
                            CFDictionaryRef trimEnd = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd);
                            CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
                            trimEndTime = CMTimeConvertScale(trimEndTime, sampleTimingInfo.duration.value, kCMTimeRoundingMethod_Default);
                            currentOutputTimeStamp.value -= trimEndTime.value;
                        }

                        [demuxHelper->editsConstructor addSample:sample];
                        [self enqueue:sample];
                        [sample release];

                        currentOutputTimeStamp.value = currentOutputTimeStamp.value + sampleTimingInfo.duration.value;
                        currentDataLength += sampleSize;
                    }

                    free(timingArrayOut);
                    free(sizeArrayOut);
                }
                else {
                    CMTime currentDuration = CMTimeConvertScale(duration, timescale, kCMTimeRoundingMethod_Default);
                    CMTime currentTimeStamp = CMTimeConvertScale(presentationTimeStamp, timescale, kCMTimeRoundingMethod_Default);
                    CMTime currentOutputTimeStamp = CMTimeConvertScale(presentationOutputTimeStamp, timescale, kCMTimeRoundingMethod_Default);

                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->duration = currentDuration.value;
                    sample->presentationTimestamp = currentTimeStamp.value;
                    sample->presentationOutputTimestamp = currentOutputTimeStamp.value;
                    sample->timescale = timescale;
                    sample->flags |= sync ? MP42SampleBufferFlagIsSync : 0;
                    sample->flags |= doNotDisplay ? MP42SampleBufferFlagDoNotDisplay : 0;
                    sample->trackId = track.sourceId;
                        
                    sample->attachments = (void *)attachments;
                        
                    [demuxHelper->editsConstructor addSample:sample];
                }
                CFRelease(sampleBuffer);

                self.progress = (((CGFloat) currentDataLength /  totalDataLength ) * 100);

            } else {
                break;
            }
        }

        [demuxHelper->editsConstructor done];
    }

    [assetReader release];
    [self setDone];
    [pool release];
}

- (BOOL)cleanUp:(MP4FileHandle)fileHandle {
    uint32_t timescale = MP4GetTimeScale(fileHandle);

    for (MP42Track *track in self.outputsTracks) {
        MP4Duration trackDuration = 0;
        MP4TrackId trackId = track.trackId;

        MP42Track *inputTrack = [self inputTrackWithTrackID:track.sourceId];

        AVFDemuxHelper *helper = inputTrack.muxer_helper->demuxer_context;
        MP42EditListsReconstructor *editsConstructor = helper->editsConstructor;

        // Make sure the sample offsets are all positive.
        if (editsConstructor.minOffset < 0) {
            MP4SampleId samplesCount = MP4GetTrackNumberOfSamples(fileHandle, trackId);
            for (unsigned int i = 0; i < samplesCount; i++) {
                MP4SetSampleRenderingOffset(fileHandle,
                                            trackId,
                                            1 + i,
                                            MP4GetSampleRenderingOffset(fileHandle, trackId, 1 + i) - editsConstructor.minOffset);
            }
        }

        // Add back the new constructed edit lists.
        for (uint64_t i = 0; i < helper->editsConstructor.editsCount; i++) {
            CMTimeRange timeRange = editsConstructor.edits[i];
            CMTime duration = CMTimeConvertScale(timeRange.duration, timescale, kCMTimeRoundingMethod_Default);
            int64_t offset = editsConstructor.minOffset < 0 ? editsConstructor.minOffset : 0;
            int64_t offset2 = editsConstructor.minOffset > 0 && timeRange.start.value == 0 ? editsConstructor.minOffset : 0;
            MP4Timestamp startTime = timeRange.start.value == -1 ? -1 : timeRange.start.value - offset + offset2;

            MP4AddTrackEdit(fileHandle, trackId, MP4_INVALID_EDIT_ID,
                            startTime,
                            duration.value, 0);

            trackDuration += duration.value;
        }

        if (trackDuration) {
            MP4SetTrackIntegerProperty(fileHandle, trackId, "tkhd.duration", trackDuration);
        }

    }
    return YES;
}

- (NSString *)description
{
    return @"AVFoundation demuxer";
}

- (void) dealloc {
    [_localAsset release];
    [super dealloc];
}

@end
