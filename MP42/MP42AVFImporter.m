//
//  MP42AVFImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2022 Damiano Galassi All rights reserved.
//

#import "MP42AVFImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42Languages.h"
#import "MP42File.h"

#import "MP42PrivateUtilities.h"
#import "MP42FormatUtilites.h"
#import "MP42Track+Private.h"
#import "MP42AudioTrack.h"

#import "MP42EditListsReconstructor.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <VideoToolbox/VideoToolbox.h>
#import <MediaToolbox/MediaToolbox.h>

MP42_OBJC_DIRECT_MEMBERS
@interface AVFDemuxHelper : NSObject {
@public
    MP42TrackId sourceID;
    CMTimeScale timescale;
    CMTimeValue currentTime;
    MP42CodecType format;

    uint32_t done;

    AVAssetReaderOutput *assetReaderOutput;
    MP42EditListsReconstructor *editsConstructor;
}

@end

@implementation AVFDemuxHelper
@end

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42AVFImporter {
    AVAsset *_localAsset;
    NSMutableArray<AVFDemuxHelper *> *_helpers;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"mov", @"qt", @"mp4", @"m4v", @"m4a", @"mxf", @"mp3", @"m2ts", @"ts", @"mts",
             @"ac3", @"eac3", @"ec3", @"webvtt", @"vtt", @"caf", @"aif", @"aiff", @"aifc", @"wav", @"flac"];
}

- (FourCharCode)formatForTrack:(AVAssetTrack *)track {
    FourCharCode result = 0;
    CMFormatDescriptionRef formatDescription = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;

    if (formatDescription) {
        FourCharCode code = CMFormatDescriptionGetMediaSubType(formatDescription);
        switch (code) {
            case 'ms \0':
                result = kMP42AudioCodecType_AC3;
                break;
            case kAudioFormatFLAC:
            case 'XiFL':
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

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError * __autoreleasing *)outError {
    if ((self = [super initWithURL:fileURL])) {

        VTRegisterProfessionalVideoWorkflowVideoDecoders();
        MTRegisterProfessionalVideoWorkflowFormatReaders();

        _localAsset = [AVAsset assetWithURL:self.fileURL];
        _helpers = [NSMutableArray array];

        NSArray<AVAssetTrack *> *tracks = _localAsset.tracks;
        CMTime globaDuration = _localAsset.duration;

        NSArray *availableChapter = [_localAsset availableChapterLocales];
        MP42ChapterTrack *chapters = nil;

        // Checks if there is a chapter tracks
        if (tracks.count) {
            for (NSLocale *locale in availableChapter) {
                chapters = [[MP42ChapterTrack alloc] init];
                NSArray *chapterList = [_localAsset chapterMetadataGroupsWithTitleLocale:locale containingItemsWithCommonKeys:nil];
                for (AVTimedMetadataGroup *chapterData in chapterList) {
                    for (AVMetadataItem *item in chapterData.items) {
                        CMTime time = item.time;
                        NSString *title = item.stringValue ? item.stringValue : @"";
                        [chapters addChapter:title timestamp:time.value * time.timescale / 1000];
                    }
                }
            }
        }

        // Converts the tracks to the MP42File types
        for (AVAssetTrack *track in tracks) {

            MP42Track *newTrack = nil;

            // Retrieves the formatDescription
            NSArray *formatDescriptions = track.formatDescriptions;
            CMFormatDescriptionRef formatDescription = (__bridge CMFormatDescriptionRef)formatDescriptions.firstObject;

            if ([track.mediaType isEqualToString:AVMediaTypeVideo]) {

                FourCharCode code = 0;
                if (formatDescription) {
                    code = CMFormatDescriptionGetMediaSubType(formatDescription);
                }

                if (code == 'SSA ') {
                    newTrack = [[MP42SubtitleTrack alloc] init];
                } else {
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
                            else {
                                videoTrack.colorPrimaries = 2;
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
                            else if (CFEqual(transferFunctions, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ)) {
                                videoTrack.transferCharacteristics = 16;
                            }
                            else if (CFEqual(transferFunctions, kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1)) {
                                videoTrack.transferCharacteristics = 17;
                            }
                            else if (CFEqual(transferFunctions, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG)) {
                                videoTrack.transferCharacteristics = 18;
                            }
                            else {
                                videoTrack.transferCharacteristics = 2;
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
                            else if (CFEqual(YCbCrMatrix, CFSTR("IPT_C2"))) {
                                videoTrack.matrixCoefficients = 15;
                            }
                            else {
                                videoTrack.matrixCoefficients = 2;
                            }
                        }

                        CFBooleanRef colorRange = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_FullRangeVideo);
                        if (colorRange) {
                            videoTrack.colorRange = CFBooleanGetValue(colorRange);
                        }

                        CFDataRef masteringExtension = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_MasteringDisplayColorVolume);
                        if (masteringExtension && CFDataGetLength(masteringExtension) >= 24) {
                            MP42MasteringDisplayMetadataPayload *masteringPayload = (MP42MasteringDisplayMetadataPayload *)CFDataGetBytePtr(masteringExtension);
                            MP42MasteringDisplayMetadata mastering;

                            const int chromaDen = 50000;
                            const int lumaDen = 10000;

                            mastering.display_primaries[0][0] = make_rational(CFSwapInt16BigToHost(masteringPayload->display_primaries_rx), chromaDen);
                            mastering.display_primaries[0][1] = make_rational(CFSwapInt16BigToHost(masteringPayload->display_primaries_ry), chromaDen);
                            mastering.display_primaries[1][0] = make_rational(CFSwapInt16BigToHost(masteringPayload->display_primaries_gx), chromaDen);
                            mastering.display_primaries[1][1] = make_rational(CFSwapInt16BigToHost(masteringPayload->display_primaries_gy), chromaDen);
                            mastering.display_primaries[2][0] = make_rational(CFSwapInt16BigToHost(masteringPayload->display_primaries_bx), chromaDen);
                            mastering.display_primaries[2][1] = make_rational(CFSwapInt16BigToHost(masteringPayload->display_primaries_by), chromaDen);

                            mastering.white_point[0] = make_rational(CFSwapInt16BigToHost(masteringPayload->white_point_x), chromaDen);
                            mastering.white_point[1] = make_rational(CFSwapInt16BigToHost(masteringPayload->white_point_y), chromaDen);

                            mastering.max_luminance = make_rational(CFSwapInt32BigToHost(masteringPayload->max_display_mastering_luminance), lumaDen);
                            mastering.min_luminance = make_rational(CFSwapInt32BigToHost(masteringPayload->min_display_mastering_luminance), lumaDen);

                            mastering.has_primaries = 1;
                            mastering.has_luminance = 1;

                            videoTrack.mastering = mastering;
                        }

                        CFDataRef collExtension = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_ContentLightLevelInfo);
                        if (collExtension && CFDataGetLength(collExtension) >= 4) {
                            MP42ContentLightMetadataPayload *collPayload = (MP42ContentLightMetadataPayload *)CFDataGetBytePtr(collExtension);
                            MP42ContentLightMetadata coll;
                            coll.MaxCLL = CFSwapInt16BigToHost(collPayload->MaxCLL);
                            coll.MaxFALL = CFSwapInt16BigToHost(collPayload->MaxFALL);

                            videoTrack.coll = coll;
                        }

                        if (@available(macOS 12.0, *)) {
                            CFDataRef ambientExtension = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_AmbientViewingEnvironment);
                            if (ambientExtension && CFDataGetLength(ambientExtension) >= 8) {
                                MP42AmbientViewingEnviroment *ambientPayload = (MP42AmbientViewingEnviroment *)CFDataGetBytePtr(ambientExtension);
                                MP42AmbientViewingEnviroment ambient;

                                ambient.ambient_illuminance = CFSwapInt32BigToHost(ambientPayload->ambient_illuminance);
                                ambient.ambient_light_x = CFSwapInt16BigToHost(ambientPayload->ambient_light_x);
                                ambient.ambient_light_y = CFSwapInt16BigToHost(ambientPayload->ambient_light_y);

                                videoTrack.ambient = ambient;
                            }
                        }

                        CFDictionaryRef extentions = CMFormatDescriptionGetExtensions(formatDescription);
                        CFDictionaryRef atoms = CFDictionaryGetValue(extentions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
                        if (atoms) {
                            CFDataRef dvExtension = CFDictionaryGetValue(atoms, @"dvcC");

                            if (!dvExtension) {
                                dvExtension = CFDictionaryGetValue(atoms, @"dvvC");
                            }
                            if (!dvExtension) {
                                dvExtension = CFDictionaryGetValue(atoms, @"dvwC");
                            }

                            if (dvExtension && CFDataGetLength(dvExtension) >= 24) {
                                MP42DolbyVisionMetadata dv;
                                uint8_t buffer[24];
                                CFDataGetBytes(dvExtension, CFRangeMake(0, 24), buffer);

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

                            CFDataRef dvELConfiguration = CFDictionaryGetValue(atoms, @"hvcE");

                            if (!dvELConfiguration) {
                                dvELConfiguration = CFDictionaryGetValue(atoms, @"avcE");
                            }

                            if (dvELConfiguration) {
                                videoTrack.dolbyVisionELConfiguration = (__bridge NSData *)(dvELConfiguration);
                            }
                        }
                    }

                    newTrack = videoTrack;
                }

            }
            else if ([track.mediaType isEqualToString:AVMediaTypeAudio]) {

                // Audio type, check the channel layout and channels number
                MP42AudioTrack *audioTrack = [[MP42AudioTrack alloc] init];

				audioTrack.extensionType = kMP42AudioEmbeddedExtension_None;

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

					FourCharCode audioFormat = CMFormatDescriptionGetMediaSubType(formatDescription);
					if (audioFormat == kAudioFormatAC3 || audioFormat == kAudioFormatEnhancedAC3) {
						audioTrack.extensionType = [self streamExtensionTypeForAudioTrack:track.trackID];
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
			[self fourCCoverrideForAtmos:newTrack];
            newTrack.trackId = track.trackID;
            newTrack.URL = self.fileURL;
            newTrack.timescale = [self timescaleForTrack:track];

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
                newTrack.dataLength = newTrack.duration * newTrack.bitrate / 1000 / 8;
            }

            NSArray<AVMetadataFormat> *formats = track.availableMetadataFormats;

            AVMetadataFormat format = AVMetadataFormatQuickTimeUserData;
            AVMetadataIdentifier taggedIdentifier = AVMetadataIdentifierQuickTimeUserDataTaggedCharacteristic;
            AVMetadataIdentifier titleIdentifier = AVMetadataQuickTimeUserDataKeyTrackName;

            if ([formats containsObject:AVMetadataFormatQuickTimeUserData]) {
                format = AVMetadataFormatQuickTimeUserData;
                taggedIdentifier = AVMetadataIdentifierQuickTimeUserDataTaggedCharacteristic;
                titleIdentifier = AVMetadataQuickTimeUserDataKeyTrackName;
            }
            else if ([formats containsObject:AVMetadataFormatISOUserData]) {
                format = AVMetadataFormatISOUserData;
                taggedIdentifier = AVMetadataIdentifierISOUserDataTaggedCharacteristic;
                titleIdentifier = AVMetadata3GPUserDataKeyTitle;
            }

            NSArray<AVMetadataItem *> *trackMetadata = [track metadataForFormat:format];

            // "name" is undefined in AVMetadataFormat.h, so read the official track name "tnam", and then "name".
            //  On 10.7, "name" is returned as an NSData
            NSString *trackName = [[[AVMetadataItem metadataItemsFromArray:trackMetadata
                                                                   withKey:titleIdentifier
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

            NSArray<AVMetadataItem *> *mediaTags = [AVMetadataItem metadataItemsFromArray:trackMetadata
                                                                     filteredByIdentifier:taggedIdentifier];

            if (mediaTags.count) {
                NSMutableSet<NSString *> *tags = [NSMutableSet set];
                
                for (AVMetadataItem *tag in mediaTags) {
                    [tags addObject:tag.stringValue];
                }
                newTrack.mediaCharacteristicTags = tags;
            }

            newTrack.enabled = track.isEnabled;

            [self addTrack:newTrack];
        }

        // Reconnect references
        for (AVAssetTrack *track in tracks) {

            NSArray<AVAssetTrack *> *fallbacks = [track associatedTracksOfType:AVTrackAssociationTypeAudioFallback];
            if (fallbacks.count) {
                MP42AudioTrack *audioTrack = [self trackWithSourceTrackID:track.trackID];
                MP42Track *fallbackTrack = [self trackWithSourceTrackID:fallbacks.firstObject.trackID];
                if (fallbackTrack && audioTrack && [audioTrack isKindOfClass:[MP42AudioTrack class]]) {
                    audioTrack.fallbackTrack = fallbackTrack;
                }
            }

            NSArray<AVAssetTrack *> *followers = [track associatedTracksOfType:AVTrackAssociationTypeSelectionFollower];
            if (followers.count) {
                MP42AudioTrack *audioTrack = [self trackWithSourceTrackID:track.trackID];
                MP42Track *followerTrack = [self trackWithSourceTrackID:followers.firstObject.trackID];
                if (followerTrack && audioTrack && [audioTrack isKindOfClass:[MP42AudioTrack class]]) {
                    audioTrack.followsTrack = followerTrack;
                }
            }

            NSArray<AVAssetTrack *> *forced = [track associatedTracksOfType:AVTrackAssociationTypeForcedSubtitlesOnly];
            if (forced.count) {
                MP42SubtitleTrack *subTrack = [self trackWithSourceTrackID:track.trackID];
                MP42Track *forcedTrack = [self trackWithSourceTrackID:forced.firstObject.trackID];
                if (forcedTrack && subTrack && [subTrack isKindOfClass:[MP42SubtitleTrack class]]) {
                    subTrack.forcedTrack = forcedTrack;
                }
            }
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

    return [result copy];
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

    for (NSString *commonKey in commonItemsDict.allKeys) {
        NSArray<AVMetadataItem *> *items = [AVMetadataItem metadataItemsFromArray:_localAsset.commonMetadata
                                                                          withKey:commonKey
                                                                         keySpace:AVMetadataKeySpaceCommon];
        if (items.count) {
            [self.metadata addMetadataItem:[self metadataItemWithValue:items.lastObject.value identifier:commonItemsDict[commonKey]]];
        }
    }

    // Copy the artworks
    NSArray<AVMetadataItem *> *items = [AVMetadataItem metadataItemsFromArray:_localAsset.commonMetadata
                                                                      withKey:AVMetadataCommonKeyArtwork
                                                                     keySpace:AVMetadataKeySpaceCommon];

    for (AVMetadataItem *item in items) {
        NSData *artworkData = item.dataValue;

        if ([artworkData isKindOfClass:[NSData class]]) {
            NSImage *imageData = [[NSImage alloc] initWithData:artworkData];
            MP42Image *image = [[MP42Image alloc] initWithImage:imageData];
            [self.metadata addMetadataItem:[self metadataItemWithValue:image identifier:MP42MetadataKeyCoverArt]];
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
                                            MP42MetadataKeyDiscCompilation,     AVMetadataiTunesMetadataKeyDiscCompilation,
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
            items = [AVMetadataItem metadataItemsFromArray:quicktimeMetadata withKey:qtKey keySpace:AVMetadataKeySpaceQuickTimeMetadata];
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

- (UInt32)timescaleForTrack:(AVAssetTrack *)track {
    // Prefer the asbd sample rate, naturalTimeScale might not be
    // the right one if we are reading from .ts
    if ([track.mediaType isEqualToString:AVMediaTypeAudio] && track.naturalTimeScale == 90000) {
        CMFormatDescriptionRef formatDescription = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;

        if (formatDescription) {
            const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
            return asbd->mSampleRate;
        }
    }
    return track.naturalTimeScale;
}

#pragma mark - Overrides

- (NSData *)magicCookieForTrack:(MP42Track *)track {

    AVAssetTrack *assetTrack = [_localAsset trackWithTrackID:track.sourceId];
    CMFormatDescriptionRef formatDescription = (__bridge CMFormatDescriptionRef)assetTrack.formatDescriptions.firstObject;

    if (formatDescription) {

        FourCharCode code = CMFormatDescriptionGetMediaSubType(formatDescription);

        if ([assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) {

            CFDictionaryRef extentions = CMFormatDescriptionGetExtensions(formatDescription);
            CFDictionaryRef atoms = CFDictionaryGetValue(extentions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
            CFDataRef magicCookie = NULL;

            if (atoms)
            {
                if (code == kCMVideoCodecType_H264 || code == kMP42VideoCodecType_DolbyVisionH264) {
                    magicCookie = CFDictionaryGetValue(atoms, @"avcC");
                }
                else if (code == kCMVideoCodecType_HEVC || code == kMP42VideoCodecType_HEVC_PSinBitstream ||
                         code == kCMVideoCodecType_DolbyVisionHEVC || code == kMP42VideoCodecType_DolbyVisionHEVC_PSinBitstream) {
                    magicCookie = CFDictionaryGetValue(atoms, @"hvcC");
                }
                else if (code == kMP42VideoCodecType_VVC || code == kMP42VideoCodecType_VVC_PSinBitstream) {
                    magicCookie = CFDictionaryGetValue(atoms, @"vvcC");
                }
                else if (code == kMP42VideoCodecType_AV1) {
                    magicCookie = CFDictionaryGetValue(atoms, @"av1C");
                }
                else if (code == kCMVideoCodecType_MPEG4Video) {
                    magicCookie = CFDictionaryGetValue(atoms, @"esds");
                }
            }

            return (__bridge NSData *)magicCookie;

        } else if ([assetTrack.mediaType isEqualToString:AVMediaTypeAudio]) {

            size_t cookieSizeOut;
            const uint8_t *cookie = CMAudioFormatDescriptionGetMagicCookie(formatDescription, &cookieSizeOut);	// Returns proper Atmos dec3 atom (in macOS 10.14.2), if proper E-AC3 stream, not AC-3-embedded!

            if (cookie == NULL || cookieSizeOut == 0) {

                if (code == kAudioFormatMPEG4AAC) {

                    // Try to find the ESDS manually
                    CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(formatDescription);
                    if (extensions != NULL) {
                        CFDataRef verbatimSampleDescription = CFDictionaryGetValue(extensions, kCMFormatDescriptionExtension_VerbatimSampleDescription);

                        if (verbatimSampleDescription != NULL) {
                            CFIndex length = CFDataGetLength(verbatimSampleDescription);
                            if (length >= 103) {
                                UInt8 *cookieBuffer = malloc(sizeof(UInt8) * length - 60);
                                CFRange range = CFRangeMake(60, length - 60);
                                CFDataGetBytes(verbatimSampleDescription, range, cookieBuffer);

                                UInt8 *buffer;
                                int size;
                                ReadESDSDescExt((void *)cookieBuffer, &buffer, &size, 1);

                                NSData *magicCookie = nil;
                                if (size) {
                                    magicCookie = [NSData dataWithBytes:buffer length:size];
                                    free(buffer);
                                }
                                free(cookieBuffer);

                                return magicCookie;
                            }
                        }
                    }
                }

                return nil;
            }

			code = [self fourCCoverrideForAtmos:track];

            if (code == kAudioFormatMPEG4AAC || code == kAudioFormatMPEG4AAC_HE || code == kAudioFormatMPEG4AAC_HE_V2) {

                // Extract DecoderSpecific info
                UInt8 *buffer;
                int size;
                ReadESDSDescExt((void *)cookie, &buffer, &size, 0);

                NSData *magicCookie = [NSData dataWithBytes:buffer length:size];
                free(buffer);
                return magicCookie;

            }

            else if (code == kAudioFormatAppleLossless) {

                if (cookieSizeOut > 48) {
                    // Remove unneeded parts of the cookie, as described in ALACMagicCookieDescription.txt
                    cookie += 24;
                    cookieSizeOut = cookieSizeOut - 24 - 8;
                }

                return [NSData dataWithBytes:cookie length:cookieSizeOut];
            }

            else if (code == kAudioFormatOpus) {
                // TODO
                return [NSData dataWithBytes:cookie length:cookieSizeOut];
            }

            else if (code == kAudioFormatFLAC || code == kMP42AudioCodecType_FLAC) {
                if (cookieSizeOut > 12) {
                    NSMutableData *magicCookie = [NSMutableData dataWithBytes:cookie + 8 length:cookieSizeOut - 8];
                    uint8_t *bytes = magicCookie.mutableBytes;
                    bytes[0] = 'f';
                    bytes[1] = 'L';
                    bytes[2] = 'a';
                    bytes[3] = 'C';
                    return magicCookie;
                }
            }

            else if (code == kAudioFormatEnhancedAC3) {
                // dec3 atom
                // remove the atom header
                cookie += 8;
                cookieSizeOut = cookieSizeOut - 8;

                if (cookieSizeOut < UINT32_MAX) {
                    NSMutableData *ac3Info = [NSMutableData dataWithBytes:cookie length:cookieSizeOut];
                    MP42AudioTrack *audiotrack = (MP42AudioTrack *)track;
                    // besides fourCC also the bsid in cookie created by CMAudioFormatDescriptionGetMagicCookie needs to be fixed
                    NSRange cookieBsidRange = NSMakeRange(2, 1);
                    uint8_t cookieBsidByte[1];
                    [ac3Info getBytes:cookieBsidByte range:cookieBsidRange];
                    cookieBsidByte[0] = (cookieBsidByte[0] & 0xC0) | (0x10 << 1);	// keep fscod, replace bsid with 0x10. This can happen, if bsid=0x10 frames are embedded as substream inside bsid=0x06 frames.
                    [ac3Info replaceBytesInRange:cookieBsidRange withBytes:cookieBsidByte length:1];
                    // dec3 atom may be already delivered as ETSI TS 103 420 V1.2.1 compliant by CMAudioFormatDescriptionGetMagicCookie(), see above.
                    UInt8 ec3ExtensionType = EC3Extension_None;
                    UInt8 complexityIndex = 0;
                    UInt32 dummy;
                    readEAC3Config(cookie, (uint32_t)cookieSizeOut, &dummy, &dummy, &ec3ExtensionType, &complexityIndex);
                    // do not add duplicate ec3ExtensionType & complexityIndex, if already present
                    if (!ec3ExtensionType && !complexityIndex && (audiotrack.extensionType == kMP42AudioEmbeddedExtension_JOC))
                    {
                        ec3ExtensionType = audiotrack.extensionType;
                        [ac3Info appendBytes:&ec3ExtensionType	length:sizeof(MP42AudioEmbeddedExtension)];
                        [ac3Info appendBytes:&complexityIndex	length:sizeof(UInt8)];
                    }
                    return ac3Info;
                } else {
                    return nil;
                }
			}

            else if (code == kAudioFormatAC3 ||
                     code == 'ms \0') {

                AudioChannelLayoutTag channelLayoutTag = kAudioChannelLabel_Unknown;

                OSStatus err = noErr;
                size_t channelLayoutSize = 0;
                const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
                const AudioChannelLayout *channelLayout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, &channelLayoutSize);

                if (channelLayout) {
                    channelLayoutTag = channelLayout->mChannelLayoutTag;
                } else {
                    size_t formatListSize = 0;
                    const AudioFormatListItem *formatList = CMAudioFormatDescriptionGetFormatList(formatDescription, &formatListSize);
                    if (formatListSize) {
                        channelLayoutTag = formatList->mChannelLayoutTag;
                    }
                }

                UInt32 bitmapSize = sizeof(UInt32);
                UInt32 channelBitmap;
                err = AudioFormatGetProperty(kAudioFormatProperty_BitmapForLayoutTag,
                                             sizeof(AudioChannelLayoutTag), &channelLayoutTag,
                                             &bitmapSize, &channelBitmap);

                if (err && AudioChannelLayoutTag_GetNumberOfChannels(channelLayoutTag) == 6) {
                    channelBitmap = 0x3F;
                }

                uint64_t fscod = 0;
                uint64_t bsid = 8;
                uint64_t bsmod = 0;
                uint64_t acmod = 7;
                uint64_t lfeon = (channelBitmap & kAudioChannelBit_LFEScreen) ? 1 : 0;
                uint64_t bit_rate_code = 15;

                switch (AudioChannelLayoutTag_GetNumberOfChannels(channelLayoutTag) - lfeon) {
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

				return ac3Info;

            } else if (cookieSizeOut) {
                return [NSData dataWithBytes:cookie length:cookieSizeOut];
            }
        }

        else if ([assetTrack.mediaType isEqualToString:AVMediaTypeText]) {

            if (code == kCMSubtitleFormatType_WebVTT) {

                CFDictionaryRef extentions = CMFormatDescriptionGetExtensions(formatDescription);
                CFDictionaryRef atoms = CFDictionaryGetValue(extentions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
                if (atoms) {
                    CFDataRef magicCookie = CFDictionaryGetValue(atoms, @"vttC");
                    return (__bridge NSData *)magicCookie;
                }
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
    CMFormatDescriptionRef formatDescription = (__bridge CMFormatDescriptionRef)assetTrack.formatDescriptions.firstObject;

    if (formatDescription) {
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
        memcpy(&result, asbd, sizeof(AudioStreamBasicDescription));
    }

    return result;
}

- (BOOL)supportsPreciseTimestamps {
    return YES;
}

- (BOOL)audioTrackUsesExplicitEncoderDelay:(MP42Track *)track
{
    return YES;
}

- (void)demux {
    @autoreleasepool {
        CMTimeValue currentTime = 1;

        uint64_t currentDataLength = 0;
        uint64_t totalDataLength = 0;

        NSUInteger tracksDone = 0;
        NSUInteger tracksNumber = self.inputTracks.count;

        AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:_localAsset error:NULL];
        AVFDemuxHelper *helpers[tracksNumber];

        if (assetReader == nil) {
            [self setDone];
            return;
        }

        for (NSUInteger index = 0; index < tracksNumber; index += 1) {
            MP42Track *track = self.inputTracks[index];
            AVAssetReaderOutput *assetReaderOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[_localAsset trackWithTrackID:track.sourceId]
                                                                                                outputSettings:nil];
            assetReaderOutput.alwaysCopiesSampleData = NO;

            if ([assetReader canAddOutput:assetReaderOutput]) {
                [assetReader addOutput:assetReaderOutput];
            } else {
                NSLog(@"Unable to add the output to assetReader!");
            }

            AVFDemuxHelper *demuxHelper = [[AVFDemuxHelper alloc] init];
            demuxHelper->sourceID = track.sourceId;
            demuxHelper->timescale = track.timescale;
            demuxHelper->format = track.format;
            demuxHelper->assetReaderOutput = assetReaderOutput;
            demuxHelper->editsConstructor = [[MP42EditListsReconstructor alloc] init];

            helpers[index] = demuxHelper;
            [_helpers addObject:demuxHelper];

            totalDataLength += track.dataLength;
        }

        if (![assetReader startReading]) {
            [self setDone];
            return;
        }

        while (tracksDone != tracksNumber) {
            if (self.isCancelled) {
                break;
            }

            for (NSUInteger index = 0; index < tracksNumber; index += 1) {
                AVFDemuxHelper *demuxHelper = helpers[index];
                AVAssetReaderOutput *assetReaderOutput = demuxHelper->assetReaderOutput;

                while (demuxHelper->currentTime < demuxHelper->timescale * currentTime && !demuxHelper->done) {
                    CMSampleBufferRef sampleBuffer = [assetReaderOutput copyNextSampleBuffer];

                    if (sampleBuffer) {

                        CMItemCount samplesNum = CMSampleBufferGetNumSamples(sampleBuffer);

                        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
                        CMTime decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
                        CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                        CMTime presentationOutputTimeStamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);

                        CMTime currentOutputTimeStamp = CMTimeConvertScale(presentationOutputTimeStamp, demuxHelper->timescale, kCMTimeRoundingMethod_Default);

                        // Read sample attachment, to mark the frame as sync
                        BOOL sync = YES;
                        BOOL doNotDisplay = NO;
                        MP42SampleDepType dependecies = MP42SampleDepTypeUnknown;

                        CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, NO);
                        if (attachmentsArray && CFArrayGetCount(attachmentsArray)) {
                            CFDictionaryRef dict = CFArrayGetValueAtIndex(attachmentsArray, 0);

                            CFBooleanRef value;
                            BOOL keyExists;

                            keyExists = CFDictionaryGetValueIfPresent(dict, kCMSampleAttachmentKey_NotSync, (const void **)&value);
                            if (keyExists) {
                                sync = !CFBooleanGetValue(value);
                            }

                            keyExists = CFDictionaryGetValueIfPresent(dict, kCMSampleAttachmentKey_DoNotDisplay, (const void **)&value);
                            if (keyExists) {
                                doNotDisplay = CFBooleanGetValue(value);
                            }

                            keyExists = CFDictionaryGetValueIfPresent(dict, kCMSampleAttachmentKey_HasRedundantCoding, (const void **)&value);
                            if (keyExists) {
                                dependecies |= CFBooleanGetValue(value) ? MP42SampleDepTypeHasRedundantCoding : MP42SampleDepTypeHasNoRedundantCoding;
                            }

                            keyExists = CFDictionaryGetValueIfPresent(dict, kCMSampleAttachmentKey_DependsOnOthers, (const void **)&value);
                            if (keyExists) {
                                dependecies |= CFBooleanGetValue(value) ? MP42SampleDepTypeIsDependent : MP42SampleDepTypeIsIndependent;
                            }

                            keyExists = CFDictionaryGetValueIfPresent(dict, kCMSampleAttachmentKey_IsDependedOnByOthers, (const void **)&value);
                            if (keyExists) {
                                dependecies |= CFBooleanGetValue(value) ? MP42SampleDepTypeHasDependents : MP42SampleDepTypeHasNoDependents;
                            }

                            keyExists = CFDictionaryGetValueIfPresent(dict, kCMSampleAttachmentKey_EarlierDisplayTimesAllowed, (const void **)&value);
                            if (keyExists && CFBooleanGetValue(value)) {
                                dependecies |= MP42SampleDepTypeEarlierDisplayTimesAllowed;
                            }
                        }

                        if (dependecies == MP42SampleDepTypeUnknown) {
                            dependecies = sync ? MP42SampleDepTypeIsIndependent : MP42SampleDepTypeIsDependent;
                        }

                        CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(NULL, sampleBuffer, kCMAttachmentMode_ShouldPropagate);

                        // Get CMBlockBufferRef to extract the actual data later
                        CMBlockBufferRef buffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                        size_t bufferSize = buffer ? CMBlockBufferGetDataLength(buffer) : 0;

                        // We have only a sample
                        // or the format is PCM, if so send only a single buffer to improve performance
                        if (buffer && (samplesNum == 1 || (samplesNum > 1 && demuxHelper->format == kMP42AudioCodecType_LinearPCM))) {

                            void *sampleData = malloc(bufferSize);
                            CMBlockBufferCopyDataBytes(buffer, 0, bufferSize, sampleData);

                            // Enqueues the new sample
                            MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                            sample->data = sampleData;
                            sample->size = (uint32_t)bufferSize;
                            sample->duration = duration.value;
                            sample->offset = -decodeTimeStamp.value + presentationTimeStamp.value;
                            sample->decodeTimestamp = decodeTimeStamp.value;
                            sample->presentationTimestamp = presentationTimeStamp.value;
                            sample->presentationOutputTimestamp = currentOutputTimeStamp.value;
                            sample->timescale = demuxHelper->timescale;
                            sample->flags |= sync ? MP42SampleBufferFlagIsSync : 0;
                            sample->flags |= doNotDisplay ? MP42SampleBufferFlagDoNotDisplay : 0;
                            sample->dependecyFlags = dependecies;
                            sample->trackId = demuxHelper->sourceID;
                            sample->attachments = (void *)attachments;

                            [demuxHelper->editsConstructor addSample:sample];
                            [self enqueue:sample];

                            demuxHelper->currentTime = currentOutputTimeStamp.value;
                        }
                        // The CMSampleBufferRef contains more than one sample
                        else if (buffer && samplesNum > 1) {
                            if (!CMSampleBufferDataIsReady(sampleBuffer)) {
                                CMSampleBufferMakeDataReady(sampleBuffer);
                            }

                            // A CMSampleBufferRef can contains an multiple samples, check how many needs to be divided to separated MP42SampleBuffers
                            // First get the array with the timings for each sample
                            CMItemCount timingArrayEntries = 0;
                            CMItemCount timingArrayEntriesNeededOut = 0;
                            OSStatus err = noErr;

                            err = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, timingArrayEntries, NULL, &timingArrayEntriesNeededOut);
                            if (err) {
                                CFRelease(sampleBuffer);
                                CFRelease(attachments);
                                continue;
                            }

                            CMSampleTimingInfo *timingArrayOut = malloc(sizeof(CMSampleTimingInfo) * timingArrayEntriesNeededOut);
                            timingArrayEntries = timingArrayEntriesNeededOut;
                            err = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, timingArrayEntries, timingArrayOut, &timingArrayEntriesNeededOut);
                            if (err) {
                                free(timingArrayOut);
                                CFRelease(sampleBuffer);
                                CFRelease(attachments);
                                continue;
                            }

                            // Then the array with the size of each sample
                            CMItemCount sizeArrayEntries = 0;
                            CMItemCount sizeArrayEntriesNeededOut = 0;
                            err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, NULL, &sizeArrayEntriesNeededOut);
                            if (err) {
                                free(timingArrayOut);
                                CFRelease(sampleBuffer);
                                CFRelease(attachments);
                                continue;
                            }

                            size_t *sizeArrayOut = malloc(sizeof(size_t) * sizeArrayEntriesNeededOut);
                            sizeArrayEntries = sizeArrayEntriesNeededOut;
                            err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, sizeArrayOut, &sizeArrayEntriesNeededOut);
                            if (err) {
                                free(timingArrayOut);
                                free(sizeArrayOut);
                                CFRelease(sampleBuffer);
                                CFRelease(attachments);
                                continue;
                            }

                            for (uint64_t i = 0, pos = 0; i < samplesNum; i++) {
                                CMSampleTimingInfo sampleTimingInfo;
                                CMTime sampleDecodeTimeStamp;
                                CMTime samplePresentationTimeStamp;

                                size_t sampleSize;

                                // If the size of sample timing array is equal to 1, it means every sample has got the same timing
                                if (timingArrayEntries == 1) {
                                    sampleTimingInfo = timingArrayOut[0];
                                    sampleDecodeTimeStamp = sampleTimingInfo.decodeTimeStamp;
                                    sampleDecodeTimeStamp.value = sampleDecodeTimeStamp.value + (sampleTimingInfo.duration.value * i);

                                    samplePresentationTimeStamp = sampleTimingInfo.presentationTimeStamp;
                                    samplePresentationTimeStamp.value = samplePresentationTimeStamp.value + (sampleTimingInfo.duration.value * i);
                                } else {
                                    sampleTimingInfo = timingArrayOut[i];
                                    //decodeTimeStamp = sampleTimingInfo.decodeTimeStamp;
                                    samplePresentationTimeStamp = sampleTimingInfo.presentationTimeStamp;
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
                                    trimStartTime = CMTimeConvertScale(trimStartTime, currentOutputTimeStamp.timescale, kCMTimeRoundingMethod_Default);
                                    currentOutputTimeStamp.value -= trimStartTime.value;
                                }

                                sample->data = sampleData;
                                sample->size = (uint32_t)sampleSize;
                                sample->duration = sampleTimingInfo.duration.value;
                                //sample->offset = -decodeTimeStamp.value + presentationTimeStamp.value;
                                sample->presentationTimestamp = samplePresentationTimeStamp.value;
                                sample->presentationOutputTimestamp = currentOutputTimeStamp.value;
                                sample->timescale = demuxHelper->timescale;
                                sample->flags |= sync ? MP42SampleBufferFlagIsSync : 0;
                                sample->flags |= doNotDisplay ? MP42SampleBufferFlagDoNotDisplay : 0;
                                sample->trackId = demuxHelper->sourceID;

                                if (attachments && i == (samplesNum - 1) && CFDictionaryContainsKey(attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd)) {
                                    CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 2, attachments);
                                    CFDictionaryRemoveValue(copy, kCMSampleBufferAttachmentKey_TrimDurationAtStart);
                                    sample->attachments = (void *)copy;
                                    CFDictionaryRef trimEnd = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd);
                                    CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
                                    trimEndTime = CMTimeConvertScale(trimEndTime, currentOutputTimeStamp.timescale, kCMTimeRoundingMethod_Default);
                                    currentOutputTimeStamp.value -= trimEndTime.value;
                                }

                                [demuxHelper->editsConstructor addSample:sample];
                                [self enqueue:sample];

                                currentOutputTimeStamp.value = currentOutputTimeStamp.value + sampleTimingInfo.duration.value;
                            }

                            demuxHelper->currentTime = currentOutputTimeStamp.value;

                            if (attachments) {
                                CFRelease(attachments);
                            }
                            free(timingArrayOut);
                            free(sizeArrayOut);
                        }
                        else {
                            CMTime currentSampleDuration = CMTimeConvertScale(duration, demuxHelper->timescale, kCMTimeRoundingMethod_Default);
                            CMTime currentSampleTimeStamp = CMTimeConvertScale(presentationTimeStamp, demuxHelper->timescale, kCMTimeRoundingMethod_Default);
                            CMTime currentSampleOutputTimeStamp = CMTimeConvertScale(presentationOutputTimeStamp, demuxHelper->timescale, kCMTimeRoundingMethod_Default);

                            MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                            sample->duration = currentSampleDuration.value;
                            sample->presentationTimestamp = currentSampleTimeStamp.value;
                            sample->presentationOutputTimestamp = currentSampleOutputTimeStamp.value;
                            sample->timescale = demuxHelper->timescale;
                            sample->flags |= sync ? MP42SampleBufferFlagIsSync : 0;
                            sample->flags |= doNotDisplay ? MP42SampleBufferFlagDoNotDisplay : 0;
                            sample->trackId = demuxHelper->sourceID;
                            sample->attachments = (void *)attachments;

                            [demuxHelper->editsConstructor addSample:sample];
                            demuxHelper->currentTime = currentSampleOutputTimeStamp.value;
                        }

                        currentDataLength += bufferSize;
                        CFRelease(sampleBuffer);

                    } else {
                        demuxHelper->done = YES;
                        [demuxHelper->editsConstructor done];
                        tracksDone += 1;
                    }
                }
            }

            self.progress = (((CGFloat) currentDataLength /  totalDataLength ) * 100);
            currentTime += 1;
        }

        [self setDone];
    }
}

- (nullable AVFDemuxHelper *)helperWithTrackID:(MP4TrackId)trackID
{
    for (AVFDemuxHelper *helper in _helpers) {
        if (helper->sourceID == trackID) {
            return helper;
        }
    }

    return nil;
}

- (nullable __kindof MP42Track *)trackWithSourceTrackID:(MP42TrackId)trackID
{
    for (MP42Track *track in self.tracks) {
        if (track.trackId == trackID) {
            return track;
        }
    }

    return nil;
}

- (void)cleanUp:(MP42Track *)track fileHandle:(MP4FileHandle)fileHandle {
    uint32_t timescale = MP4GetTimeScale(fileHandle);

    MP4Duration trackDuration = 0;
    MP4TrackId trackId = track.trackId;

    AVFDemuxHelper *helper = [self helperWithTrackID:track.sourceId];
    MP42EditListsReconstructor *editsConstructor = helper->editsConstructor;

    // Make sure the sample offsets are all positive.
    if (editsConstructor.minOffset < 0) {
        MP4SampleId samplesCount = MP4GetTrackNumberOfSamples(fileHandle, trackId);
        for (unsigned int i = 0; i < samplesCount; i++) {
            MP4SetSampleRenderingOffset(fileHandle,
                                        trackId,
                                        1 + i,
                                        (int64_t)MP4GetSampleRenderingOffset(fileHandle, trackId, 1 + i) - editsConstructor.minOffset);
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

- (NSString *)description
{
    return @"AVFoundation demuxer";
}

#pragma mark - Atmos

- (MP42AudioEmbeddedExtension)streamExtensionTypeForAudioTrack:(CMPersistentTrackID)trackID
{
    EAC3Info *eac3Info = NULL;
    SInt64 count = 0;

    @autoreleasepool {

        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:_localAsset error:NULL];
        AVAssetReaderOutput *readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[_localAsset trackWithTrackID:trackID]
                                                                                       outputSettings:nil];
        readerOutput.alwaysCopiesSampleData = NO;

        if ([reader canAddOutput:readerOutput]) {
            [reader addOutput:readerOutput];

            if ([reader startReading]) {

                while (count <= 10) {

                    CMSampleBufferRef sampleBuffer = [readerOutput copyNextSampleBuffer];
                    if (sampleBuffer) {

                        // Get CMBlockBufferRef to extract the actual data later
                        CMBlockBufferRef buffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                        size_t bufferSize = CMBlockBufferGetDataLength(buffer);

                        CMItemCount samplesNum = CMSampleBufferGetNumSamples(sampleBuffer);

                        if (samplesNum == 1) {
                            void *sampleData = malloc(bufferSize);
                            CMBlockBufferCopyDataBytes(buffer, 0, bufferSize, sampleData);

                            if (bufferSize < UINT32_MAX) {
                                analyze_EAC3((void *)&eac3Info, sampleData, (uint32_t)bufferSize);
                            }

                            free(sampleData);
                            count++;
                        } else {
                            OSStatus err = noErr;

                            // Then the array with the size of each sample
                            CMItemCount sizeArrayEntries = 0;
                            CMItemCount sizeArrayEntriesNeededOut = 0;
                            err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, NULL, &sizeArrayEntriesNeededOut);
                            if (err) {
                                CFRelease(sampleBuffer);
                                continue;
                            }

                            size_t *sizeArrayOut = malloc(sizeof(size_t) * sizeArrayEntriesNeededOut);
                            sizeArrayEntries = sizeArrayEntriesNeededOut;
                            err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, sizeArrayOut, &sizeArrayEntriesNeededOut);
                            if (err) {
                                free(sizeArrayOut);
                                CFRelease(sampleBuffer);
                                continue;
                            }

                            for (uint64_t i = 0, pos = 0; i < samplesNum; i++) {

                                size_t sampleSize;

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

                                if (sampleSize < UINT32_MAX) {
                                    analyze_EAC3((void *)&eac3Info, sampleData, (uint32_t)sampleSize);
                                }

                                free(sampleData);
                                count++;
                            }
                            free(sizeArrayOut);
                        }
                        CFRelease(sampleBuffer);
                    }
                }
            }

            [reader cancelReading];
        }
    }

    MP42AudioEmbeddedExtension result = kMP42AudioEmbeddedExtension_None;

    if (eac3Info) {
        if (eac3Info->ec3_extension_type == EC3Extension_JOC) {
            result = kMP42AudioEmbeddedExtension_JOC;
        }
        free_EAC3_context(eac3Info);
    }

	return result;
}

- (FourCharCode)fourCCoverrideForAtmos:(MP42Track *)track {
	// ugly hack to support AC-3 embedded E-AC-3 substreams that may carry JOC (Atmos)
	// otherwise magicCookieForTrack will create a wrong cookie as for AC-3
	if ([track isMemberOfClass:[MP42AudioTrack class]]) {
		if (track.format == kMP42AudioCodecType_AC3) {
			MP42AudioTrack *audioTrack = (MP42AudioTrack *)track;
			if (audioTrack.extensionType ==  kMP42AudioEmbeddedExtension_JOC) {
				track.format = kMP42AudioCodecType_EnhancedAC3;
			}
		}
	}
	return track.format;
}

@end
