//
//  MP42MkvFileImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#if __MAC_OS_X_VERSION_MAX_ALLOWED > 1060

#import "MP42AVFImporter.h"
#import "MP42Languages.h"
#import "MP42File.h"
#import "MP42Image.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Muxer.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AVFDemuxHelper : NSObject {
@public
    CMTimeRange         *edits;
    uint64_t             editsCount;
    uint64_t             editsSize;
    BOOL                 editOpen;
    int64_t              currentTime;
    AVAssetReaderOutput *assetReaderOutput;
}
@end

@implementation AVFDemuxHelper
@end

@implementation MP42AVFImporter

- (NSString *)formatForTrack:(AVAssetTrack *)track {
    NSString *result = @"";
    
    CMFormatDescriptionRef formatDescription = NULL;
    NSArray *formatDescriptions = track.formatDescriptions;
    if ([formatDescriptions count] > 0)
        formatDescription = (CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];
    
    if (formatDescription) {
        FourCharCode code = CMFormatDescriptionGetMediaSubType(formatDescription);
        switch (code) {
            case kCMVideoCodecType_H264:
                result = MP42VideoFormatH264;
                break;
            case kCMVideoCodecType_MPEG4Video:
                result = MP42VideoFormatMPEG4Visual;
                break;
            case kCMVideoCodecType_MPEG2Video:
                result = MP42VideoFormatMPEG2;
                break;
            case kCMVideoCodecType_MPEG1Video:
                result = MP42VideoFormatMPEG1;
                break;
            case kCMVideoCodecType_AppleProRes422:
            case kCMVideoCodecType_AppleProRes422HQ:
            case kCMVideoCodecType_AppleProRes422LT:
            case kCMVideoCodecType_AppleProRes422Proxy:
            case kCMVideoCodecType_AppleProRes4444:
                result = MP42VideoFormatProRes;
                break;
            case kCMVideoCodecType_SorensonVideo3:
                result = MP42VideoFormatSorenson3;
                break;
            case 'png ':
                result = MP42VideoFormatPNG;
                break;
            case kAudioFormatMPEG4AAC:
                result = MP42AudioFormatAAC;
                break;
            case kAudioFormatMPEG4AAC_HE:
            case kAudioFormatMPEG4AAC_HE_V2:
                result = MP42AudioFormatHEAAC;
                break;
            case kAudioFormatLinearPCM:
                result = MP42AudioFormatPCM;
                break;
            case kAudioFormatAppleLossless:
                result = MP42AudioFormatALAC;
                break;
            case kAudioFormatAC3:
            case 'ms \0':
                result = MP42AudioFormatAC3;
                break;
            case kAudioFormatMPEGLayer1:
            case kAudioFormatMPEGLayer2:
            case kAudioFormatMPEGLayer3:
                result = MP42AudioFormatMP3;
                break;
            case kAudioFormatAMR:
                result = MP42AudioFormatAMR;
                break;
            case kAudioFormatAppleIMA4:
                result = @"IMA 4:1";
                break;
            case kCMTextFormatType_QTText:
                result = MP42SubtitleFormatText;
                break;
            case kCMTextFormatType_3GText:
                result = MP42SubtitleFormatTx3g;
                break;
            case 'SRT ':
                result = MP42SubtitleFormatText;
                break;
            case 'SSA ':
                result = MP42SubtitleFormatSSA;
                break;
            case kCMClosedCaptionFormatType_CEA608:
                result = MP42ClosedCaptionFormatCEA608;
                break;
            case kCMClosedCaptionFormatType_CEA708:
                result = MP42ClosedCaptionFormatCEA708;
                break;
            case kCMClosedCaptionFormatType_ATSC:
                result = @"ATSC/52 part-4";
                break;
            case kCMTimeCodeFormatType_TimeCode32:
            case kCMTimeCodeFormatType_TimeCode64:
            case kCMTimeCodeFormatType_Counter32:
            case kCMTimeCodeFormatType_Counter64:
                result = MP42TimeCodeFormat;
                break;
            case kCMVideoCodecType_JPEG:
                result = MP42VideoFormatJPEG;
                break;
            case kCMVideoCodecType_DVCNTSC:
            case kCMVideoCodecType_DVCPAL:
                result = MP42VideoFormatDV;
                break;
            case kCMVideoCodecType_DVCProPAL:
            case kCMVideoCodecType_DVCPro50NTSC:
            case kCMVideoCodecType_DVCPro50PAL:
                result = @"DVCPro";
                break;
            case kCMVideoCodecType_DVCPROHD720p60:
            case kCMVideoCodecType_DVCPROHD720p50:
            case kCMVideoCodecType_DVCPROHD1080i60:
            case kCMVideoCodecType_DVCPROHD1080i50:
            case kCMVideoCodecType_DVCPROHD1080p30:
            case kCMVideoCodecType_DVCPROHD1080p25:
                result = @"DVCProHD";
                break;
            case 'AVdn':
                result = @"DNxHD";
                break;
            default:
                result = @"Unknown";
                break;
        }
    }
    return result;
}

- (NSString *)langForTrack:(AVAssetTrack *)track {
    return [NSString stringWithUTF8String:lang_for_qtcode([[track languageCode] integerValue])->eng_name];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)outError {
    if ((self = [super init])) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        _fileURL = [fileURL retain];
        _localAsset = [[AVAsset assetWithURL:_fileURL] retain];

        _tracksArray = [[NSMutableArray alloc] init];
        NSArray *tracks = [_localAsset tracks];

        NSArray *availableChapter = [_localAsset availableChapterLocales];
        MP42ChapterTrack *chapters = nil;

        if ([tracks count]) {
            for (NSLocale *locale in availableChapter) {
                chapters = [[MP42ChapterTrack alloc] init];
                NSArray *chapterList = [_localAsset chapterMetadataGroupsWithTitleLocale:locale containingItemsWithCommonKeys:nil];
                for (AVTimedMetadataGroup* chapterData in chapterList) {
                    for (AVMetadataItem *item in [chapterData items]) {
                        CMTime time = [item time];
                        [chapters addChapter:[item stringValue] duration:time.value * time.timescale / 1000];
                    }
                }
            }
        }

        for (AVAssetTrack *track in tracks) {
            MP42Track *newTrack = nil;

            CMFormatDescriptionRef formatDescription = NULL;
            NSArray *formatDescriptions = track.formatDescriptions;
			if ([formatDescriptions count] > 0)
				formatDescription = (CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];

            NSArray *trackMetadata = [track metadataForFormat:AVMetadataFormatQuickTimeUserData];

            if ([[track mediaType] isEqualToString:AVMediaTypeVideo]) {
                newTrack = [[MP42VideoTrack alloc] init];
                CGSize naturalSize = [track naturalSize];

                [(MP42VideoTrack*)newTrack setTrackWidth: naturalSize.width];
                [(MP42VideoTrack*)newTrack setTrackHeight: naturalSize.height];

                [(MP42VideoTrack*)newTrack setWidth: naturalSize.width];
                [(MP42VideoTrack*)newTrack setHeight: naturalSize.height];

                if (formatDescription) {
                    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                    [(MP42VideoTrack*)newTrack setWidth: dimensions.width];
                    [(MP42VideoTrack*)newTrack setHeight: dimensions.height];

                    // Reads the pixel aspect ratio information
                    CFDictionaryRef pixelAspectRatioFromCMFormatDescription = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_PixelAspectRatio);
                    if (pixelAspectRatioFromCMFormatDescription) {
                        NSInteger hSpacing, vSpacing;
                        CFNumberGetValue(CFDictionaryGetValue(pixelAspectRatioFromCMFormatDescription, kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing), kCFNumberIntType, &hSpacing);
                        CFNumberGetValue(CFDictionaryGetValue(pixelAspectRatioFromCMFormatDescription, kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing), kCFNumberIntType, &vSpacing);
                        [(MP42VideoTrack*)newTrack setHSpacing:hSpacing];
                        [(MP42VideoTrack*)newTrack setVSpacing:vSpacing];
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

                        [(MP42VideoTrack*)newTrack setCleanApertureWidthN:cleanApertureWidth];
                        [(MP42VideoTrack*)newTrack setCleanApertureWidthD:1];
                        [(MP42VideoTrack*)newTrack setCleanApertureHeightN:cleanApertureHeight];
                        [(MP42VideoTrack*)newTrack setCleanApertureHeightD:1];
                        [(MP42VideoTrack*)newTrack setHorizOffN:cleanApertureHorizontalOffset];
                        [(MP42VideoTrack*)newTrack setHorizOffD:1];
                        [(MP42VideoTrack*)newTrack setVertOffN:cleanApertureVerticalOffset];
                        [(MP42VideoTrack*)newTrack setVertOffD:1];
                    }
                }
            } else if ([[track mediaType] isEqualToString:AVMediaTypeAudio]) {
                newTrack = [[MP42AudioTrack alloc] init];

                if (formatDescription) {
                    size_t layoutSize = 0;
                    const AudioChannelLayout *layout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, &layoutSize);

                    if (layoutSize) {
                        [(MP42AudioTrack*)newTrack setChannels:AudioChannelLayoutTag_GetNumberOfChannels(layout->mChannelLayoutTag)];
                        [(MP42AudioTrack*)newTrack setChannelLayoutTag:layout->mChannelLayoutTag];
                    } else {
                        [(MP42AudioTrack*)newTrack setChannels:1];
                    }
                }
            } else if ([[track mediaType] isEqualToString:AVMediaTypeSubtitle]) {
                newTrack = [[MP42SubtitleTrack alloc] init];
            } else if ([[track mediaType] isEqualToString:AVMediaTypeText]) {
                // It looks like there is no way to know what text track is used for chapters in the original file.
                if (chapters)
                    newTrack = chapters;
                else
                    newTrack = [[MP42ChapterTrack alloc] init];
            } else {
                newTrack = [[MP42Track alloc] init];
            }

            newTrack.format = [self formatForTrack:track];
            newTrack.Id = [track trackID];
            newTrack.sourceURL = _fileURL;
            newTrack.dataLength = [track totalSampleDataLength];

            // "name" is undefined in AVMetadataFormat.h, so read the official track name "tnam", and then "name". On 10.7, "name" is returned as an NSData
            id trackName = [[[AVMetadataItem metadataItemsFromArray:trackMetadata withKey:AVMetadataQuickTimeUserDataKeyTrackName keySpace:nil] lastObject] value];
            id trackName_oldFormat = [[[AVMetadataItem metadataItemsFromArray:trackMetadata withKey:@"name" keySpace:nil] lastObject] value];
            if (trackName && [trackName isKindOfClass:[NSString class]]) {
                newTrack.name = trackName;
            } else if (trackName_oldFormat && [trackName_oldFormat isKindOfClass:[NSString class]]) {
                newTrack.name = trackName_oldFormat;
            } else if (trackName_oldFormat && [trackName_oldFormat isKindOfClass:[NSData class]]) {
                newTrack.name = [NSString stringWithCString:[trackName_oldFormat bytes] encoding:NSMacOSRomanStringEncoding];
            }

            newTrack.language = [self langForTrack:track];

            CMTimeRange timeRange = [track timeRange];
            newTrack.duration = timeRange.duration.value / timeRange.duration.timescale * 1000;

            [_tracksArray addObject:newTrack];
            [newTrack release];
        }

        [self convertMetadata];

        [pool release];
    }

    return self;
}

-(void)convertMetadata {
    NSArray *items = nil;
    NSDictionary *commonItemsDict = [NSDictionary dictionaryWithObjectsAndKeys:@"Name", AVMetadataCommonKeyTitle,
                                     //nil, AVMetadataCommonKeyCreator,
                                     //nil, AVMetadataCommonKeySubject,
                                     @"Description", AVMetadataCommonKeyDescription,
                                     @"Publisher", AVMetadataCommonKeyPublisher,
                                     //nil, AVMetadataCommonKeyContributor,
                                     @"Release Date", AVMetadataCommonKeyCreationDate,
                                     //nil, AVMetadataCommonKeyLastModifiedDate,
                                     @"Genre", AVMetadataCommonKeyType,
                                     //nil, AVMetadataCommonKeyFormat,
                                     //nil, AVMetadataCommonKeyIdentifier,
                                     //nil, AVMetadataCommonKeySource,
                                     //nil, AVMetadataCommonKeyLanguage,
                                     //nil, AVMetadataCommonKeyRelation,
                                     //nil, AVMetadataCommonKeyLocation,
                                     @"Copyright", AVMetadataCommonKeyCopyrights,
                                     @"Album", AVMetadataCommonKeyAlbumName,
                                     //nil, AVMetadataCommonKeyAuthor,
                                     //nil, AVMetadataCommonKeyArtwork
                                     @"Artist", AVMetadataCommonKeyArtist,
                                     //nil, AVMetadataCommonKeyMake,
                                     //nil, AVMetadataCommonKeyModel,
                                     @"Encoding Tool", AVMetadataCommonKeySoftware,
                                     nil];

    _metadata = [[MP42Metadata alloc] init];

    for (NSString *commonKey in [commonItemsDict allKeys]) {
        items = [AVMetadataItem metadataItemsFromArray:_localAsset.commonMetadata withKey:commonKey keySpace:AVMetadataKeySpaceCommon];
        if ([items count])
            [_metadata setTag:[[items lastObject] value] forKey:[commonItemsDict objectForKey:commonKey]];
    }

    items = [AVMetadataItem metadataItemsFromArray:_localAsset.commonMetadata withKey:AVMetadataCommonKeyArtwork keySpace:AVMetadataKeySpaceCommon];
    if ([items count]) {
        id artworkData = [[items lastObject] value];
        if ([artworkData isKindOfClass:[NSData class]]) {
            NSImage *image = [[NSImage alloc] initWithData:artworkData];
            [_metadata.artworks addObject:[[[MP42Image alloc] initWithImage:image] autorelease]];
            [image release];
        }
    }

    NSArray* availableMetadataFormats = [_localAsset availableMetadataFormats];

    if ([availableMetadataFormats containsObject:AVMetadataFormatiTunesMetadata]) {
        NSArray* itunesMetadata = [_localAsset metadataForFormat:AVMetadataFormatiTunesMetadata];
        
        NSDictionary *itunesMetadataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                            @"Album",               AVMetadataiTunesMetadataKeyAlbum,
                                            @"Artist",              AVMetadataiTunesMetadataKeyArtist,
                                            @"Comments",            AVMetadataiTunesMetadataKeyUserComment,
                                            //AVMetadataiTunesMetadataKeyCoverArt,
                                            @"Copyright",           AVMetadataiTunesMetadataKeyCopyright,
                                            @"Release Date",        AVMetadataiTunesMetadataKeyReleaseDate,
                                            @"Encoded By",          AVMetadataiTunesMetadataKeyEncodedBy,
                                            //@"Genre",               AVMetadataiTunesMetadataKeyPredefinedGenre,
                                            @"Genre",               AVMetadataiTunesMetadataKeyUserGenre,
                                            @"Name",                AVMetadataiTunesMetadataKeySongName,
                                            @"Track Sub-Title",     AVMetadataiTunesMetadataKeyTrackSubTitle,
                                            @"Encoding Tool",       AVMetadataiTunesMetadataKeyEncodingTool,
                                            @"Composer",            AVMetadataiTunesMetadataKeyComposer,
                                            @"Album Artist",        AVMetadataiTunesMetadataKeyAlbumArtist,
                                            @"iTunes Account Type", AVMetadataiTunesMetadataKeyAccountKind,
                                            @"iTunes Account",      AVMetadataiTunesMetadataKeyAppleID,
                                            @"artistID",            AVMetadataiTunesMetadataKeyArtistID,
                                            @"content ID",          AVMetadataiTunesMetadataKeySongID,
                                            @"Compilation",         AVMetadataiTunesMetadataKeyDiscCompilation,
                                            @"Disk #",              AVMetadataiTunesMetadataKeyDiscNumber,
                                            @"genreID",             AVMetadataiTunesMetadataKeyGenreID,
                                            @"Grouping",            AVMetadataiTunesMetadataKeyGrouping,
                                            @"playlistID",          AVMetadataiTunesMetadataKeyPlaylistID,
                                            @"Content Rating",      AVMetadataiTunesMetadataKeyContentRating,
                                            @"Rating",              @"com.apple.iTunes.iTunEXTC",
                                            @"Tempo",               AVMetadataiTunesMetadataKeyBeatsPerMin,
                                            @"Track #",             AVMetadataiTunesMetadataKeyTrackNumber,
                                            @"Art Director",        AVMetadataiTunesMetadataKeyArtDirector,
                                            @"Arranger",            AVMetadataiTunesMetadataKeyArranger,
                                            @"Lyricist",            AVMetadataiTunesMetadataKeyAuthor,
                                            @"Lyrics",              AVMetadataiTunesMetadataKeyLyrics,
                                            @"Acknowledgement",     AVMetadataiTunesMetadataKeyAcknowledgement,
                                            @"Conductor",           AVMetadataiTunesMetadataKeyConductor,
                                            @"Song Description",    AVMetadataiTunesMetadataKeyDescription,
                                            @"Description",         @"desc",
                                            @"Long Description",    @"ldes",
                                            @"Media Kind",          @"stik",
                                            @"TV Show",             @"tvsh",
                                            @"TV Episode #",        @"tves",
                                            @"TV Network",          @"tvnn",
                                            @"TV Episode ID",       @"tven",
                                            @"TV Season",           @"tvsn",
                                            @"HD Video",            @"hdvd",
                                            @"Gapless",             @"pgap",
                                            @"Sort Name",           @"sonm",
                                            @"Sort Artist",         @"soar",
                                            @"Sort Album Artist",   @"soaa",
                                            @"Sort Album",          @"soal",
                                            @"Sort Composer",       @"soco",
                                            @"Sort TV Show",        @"sosn",
                                            @"Category",            @"catg",
                                            @"iTunes U",            @"itnu",
                                            @"Purchase Date",       @"purd",
                                            @"Director",            AVMetadataiTunesMetadataKeyDirector,
                                            //AVMetadataiTunesMetadataKeyEQ,
                                            @"Linear Notes",        AVMetadataiTunesMetadataKeyLinerNotes,
                                            @"Record Company",      AVMetadataiTunesMetadataKeyRecordCompany,
                                            @"Original Artist",     AVMetadataiTunesMetadataKeyOriginalArtist,
                                            @"Phonogram Rights",    AVMetadataiTunesMetadataKeyPhonogramRights,
                                            @"Producer",            AVMetadataiTunesMetadataKeyProducer,
                                            @"Performer",           AVMetadataiTunesMetadataKeyPerformer,
                                            @"Publisher",           AVMetadataiTunesMetadataKeyPublisher,
                                            @"Sound Engineer",      AVMetadataiTunesMetadataKeySoundEngineer,
                                            @"Soloist",             AVMetadataiTunesMetadataKeySoloist,
                                            @"Credits",             AVMetadataiTunesMetadataKeyCredits,
                                            @"Thanks",              AVMetadataiTunesMetadataKeyThanks,
                                            @"Online Extras",       AVMetadataiTunesMetadataKeyOnlineExtras,
                                            @"Executive Producer",  AVMetadataiTunesMetadataKeyExecProducer,
                                            nil];

        for (NSString *itunesKey in [itunesMetadataDict allKeys]) {
            items = [AVMetadataItem metadataItemsFromArray:itunesMetadata withKey:itunesKey keySpace:AVMetadataKeySpaceiTunes];
            if ([items count]) {
                [_metadata setTag:[[items lastObject] value] forKey:[itunesMetadataDict objectForKey:itunesKey]];
            }
        }

        /*items = [AVMetadataItem metadataItemsFromArray:itunesMetadata withKey:AVMetadataiTunesMetadataKeyCoverArt keySpace:AVMetadataKeySpaceiTunes];
        if ([items count]) {
            id artworkData = [[items lastObject] value];
            if ([artworkData isKindOfClass:[NSData class]]) {
                NSImage *image = [[NSImage alloc] initWithData:artworkData];
                [_metadata.artworks addObject:[[[MP42Image alloc] initWithImage:image] autorelease]];
                [image release];
            }
        }*/
    }
    if ([availableMetadataFormats containsObject:AVMetadataFormatQuickTimeMetadata]) {
        NSArray* quicktimeMetadata = [_localAsset metadataForFormat:AVMetadataFormatQuickTimeMetadata];
        
        NSDictionary *quicktimeMetadataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                               @"Arist",        AVMetadataQuickTimeMetadataKeyAuthor,
                                               @"Comments",     AVMetadataQuickTimeMetadataKeyComment,
                                               @"Copyright",    AVMetadataQuickTimeMetadataKeyCopyright,
                                               @"Release Date", AVMetadataQuickTimeMetadataKeyCreationDate,
                                               @"Director",     AVMetadataQuickTimeMetadataKeyDirector,
                                               @"Name",         AVMetadataQuickTimeMetadataKeyDisplayName,
                                               @"Description",  AVMetadataQuickTimeMetadataKeyInformation,
                                               @"Keyworkds",    AVMetadataQuickTimeMetadataKeyKeywords,
                                               @"Producer",     AVMetadataQuickTimeMetadataKeyProducer,
                                               @"Publisher",    AVMetadataQuickTimeMetadataKeyPublisher,
                                               @"Album",        AVMetadataQuickTimeMetadataKeyAlbum,
                                               @"Artist",       AVMetadataQuickTimeMetadataKeyArtist,
                                               @"Description",  AVMetadataQuickTimeMetadataKeyDescription,
                                               @"Encoding Tool",AVMetadataQuickTimeMetadataKeySoftware,
                                               @"Genre",        AVMetadataQuickTimeMetadataKeyGenre,
                                               //AVMetadataQuickTimeMetadataKeyiXML,
                                               @"Arranger",     AVMetadataQuickTimeMetadataKeyArranger,
                                               @"Encoded By",   AVMetadataQuickTimeMetadataKeyEncodedBy,
                                               @"Original Artist",  AVMetadataQuickTimeMetadataKeyOriginalArtist,
                                               @"Performer",    AVMetadataQuickTimeMetadataKeyPerformer,
                                               @"Composer",     AVMetadataQuickTimeMetadataKeyComposer,
                                               @"Credits",      AVMetadataQuickTimeMetadataKeyCredits,
                                               @"Phonogram Rights", AVMetadataQuickTimeMetadataKeyPhonogramRights,
                                               @"Name",         AVMetadataQuickTimeMetadataKeyTitle, nil];
        
        for (NSString *qtKey in [quicktimeMetadataDict allKeys]) {
            items = [AVMetadataItem metadataItemsFromArray:quicktimeMetadata withKey:qtKey keySpace:AVMetadataKeySpaceQuickTimeUserData];
            if ([items count]) {
                [_metadata setTag:[[items lastObject] value] forKey:[quicktimeMetadataDict objectForKey:qtKey]];
            }
        }
    }
    if ([availableMetadataFormats containsObject:AVMetadataFormatQuickTimeUserData]) {
        NSArray* quicktimeUserDataMetadata = [_localAsset metadataForFormat:AVMetadataFormatQuickTimeUserData];
        
        NSDictionary *quicktimeUserDataMetadataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                                       @"Album",                AVMetadataQuickTimeUserDataKeyAlbum,
                                                       @"Arranger",             AVMetadataQuickTimeUserDataKeyArranger,
                                                       @"Artist",               AVMetadataQuickTimeUserDataKeyArtist,
                                                       @"Lyricist",             AVMetadataQuickTimeUserDataKeyAuthor,
                                                       @"Comments",             AVMetadataQuickTimeUserDataKeyComment,
                                                       @"Composer",             AVMetadataQuickTimeUserDataKeyComposer,
                                                       @"Copyright",            AVMetadataQuickTimeUserDataKeyCopyright,
                                                       @"Release Date",         AVMetadataQuickTimeUserDataKeyCreationDate,
                                                       @"Description",          AVMetadataQuickTimeUserDataKeyDescription,
                                                       @"Director",             AVMetadataQuickTimeUserDataKeyDirector,
                                                       @"Encoded By",           AVMetadataQuickTimeUserDataKeyEncodedBy,
                                                       @"Name",                 AVMetadataQuickTimeUserDataKeyFullName,
                                                       @"Genre",                AVMetadataQuickTimeUserDataKeyGenre,
                                                       @"Keywords",             AVMetadataQuickTimeUserDataKeyKeywords,
                                                       @"Original Artist",      AVMetadataQuickTimeUserDataKeyOriginalArtist,
                                                       @"Performer",            AVMetadataQuickTimeUserDataKeyPerformers,
                                                       @"Producer",             AVMetadataQuickTimeUserDataKeyProducer,
                                                       @"Publisher",            AVMetadataQuickTimeUserDataKeyPublisher,
                                                       @"Online Extras",        AVMetadataQuickTimeUserDataKeyURLLink,
                                                       @"Credits",              AVMetadataQuickTimeUserDataKeyCredits,
                                                       @"Phonogram Rights",     AVMetadataQuickTimeUserDataKeyPhonogramRights, nil];

        for (NSString *qtUserDataKey in [quicktimeUserDataMetadataDict allKeys]) {
            items = [AVMetadataItem metadataItemsFromArray:quicktimeUserDataMetadata withKey:qtUserDataKey keySpace:AVMetadataKeySpaceQuickTimeUserData];
            if ([items count]) {
                [_metadata setTag:[[items lastObject] value] forKey:[quicktimeUserDataMetadataDict objectForKey:qtUserDataKey]];
            }
        }
    }
}

- (NSUInteger)timescaleForTrack:(MP42Track *)track {
    AVAssetTrack *assetTrack = [_localAsset trackWithTrackID:[track sourceId]];

    CMFormatDescriptionRef formatDescription = NULL;
    NSArray *formatDescriptions = assetTrack.formatDescriptions;
    if ([formatDescriptions count] > 0)
        formatDescription = (CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];
        if ([[assetTrack mediaType] isEqualToString:AVMediaTypeAudio]) {
            const AudioStreamBasicDescription* const asbd =
            CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);

            double sampleRate = asbd->mSampleRate;

            return (NSUInteger)sampleRate;
    }

    return [assetTrack naturalTimeScale];
}

- (NSSize)sizeForTrack:(MP42Track *)track {
    MP42VideoTrack *currentTrack = (MP42VideoTrack *)track;

    return NSMakeSize([currentTrack width], [currentTrack height]);
}

- (NSData *)magicCookieForTrack:(MP42Track *)track {
    AVAssetTrack *assetTrack = [_localAsset trackWithTrackID:[track sourceId]];

    CMFormatDescriptionRef formatDescription = NULL;
    NSArray *formatDescriptions = assetTrack.formatDescriptions;
    if ([formatDescriptions count] > 0)
        formatDescription = (CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];

    if (formatDescription) {
        FourCharCode code = CMFormatDescriptionGetMediaSubType(formatDescription);
        if ([[assetTrack mediaType] isEqualToString:AVMediaTypeVideo]) {
            CFDictionaryRef extentions = CMFormatDescriptionGetExtensions(formatDescription);
            CFDictionaryRef atoms = CFDictionaryGetValue(extentions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
            CFDataRef magicCookie = NULL;

            if (code == kCMVideoCodecType_H264) 
                magicCookie = CFDictionaryGetValue(atoms, @"avcC");
            else if (code == kCMVideoCodecType_MPEG4Video)
                magicCookie = CFDictionaryGetValue(atoms, @"esds");

            return (NSData*)magicCookie;
        } else if ([[assetTrack mediaType] isEqualToString:AVMediaTypeAudio]) {
            size_t cookieSizeOut;
            const void *magicCookie = CMAudioFormatDescriptionGetMagicCookie(formatDescription, &cookieSizeOut);

            if (code == kAudioFormatMPEG4AAC || code == kAudioFormatMPEG4AAC_HE || code == kAudioFormatMPEG4AAC_HE_V2) {
                // Extract DecoderSpecific info
                UInt8* buffer;
                int size;
                ReadESDSDescExt((void*)magicCookie, &buffer, &size, 0);

                return [NSData dataWithBytes:buffer length:size];
            } else if (code == kAudioFormatAppleLossless) {
                if (cookieSizeOut > 48) {
                    // Remove unneeded parts of the cookie, as describred in ALACMagicCookieDescription.txt
                    magicCookie += 24;
                    cookieSizeOut = cookieSizeOut - 24 - 8;
                }

                return [NSData dataWithBytes:magicCookie length:cookieSizeOut];
            } else if (code == kAudioFormatAC3) {
                OSStatus err = noErr;
                size_t channelLayoutSize = 0;
                const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
                const AudioChannelLayout* channelLayout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, &channelLayoutSize);

                UInt32 bitmapSize = sizeof(UInt32);
                UInt32 channelBitmap;
                err = AudioFormatGetProperty(kAudioFormatProperty_BitmapForLayoutTag,
                                               sizeof(AudioChannelLayoutTag), &channelLayout->mChannelLayoutTag,
                                               &bitmapSize, &channelBitmap);
                if (err && AudioChannelLayoutTag_GetNumberOfChannels(channelLayout->mChannelLayoutTag) == 6)
                    channelBitmap = 0x3F;

                uint8_t fscod = 0;
                uint8_t bsid = 8;
                uint8_t bsmod = 0;
                uint8_t acmod = 7;
                uint8_t lfeon = (channelBitmap & kAudioChannelBit_LFEScreen) ? 1 : 0;
                uint8_t bit_rate_code = 15;

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

            } else if (cookieSizeOut)
                return [NSData dataWithBytes:magicCookie length:cookieSizeOut];
        }
    }
    return nil;
}

/**
 * Starts a new edit
 */
- (void)startEditListAtTime:(CMTime)time helper:(AVFDemuxHelper *)helper {
    if (helper->editsSize <= helper->editsCount) {
        helper->editsSize += 20;
        helper->edits = (CMTimeRange *) realloc(helper->edits, sizeof(CMTimeRange) * helper->editsSize);
    }
    helper->edits[helper->editsCount] = CMTimeRangeMake(time, kCMTimeInvalid);
    helper->editOpen = YES;
}

/**
 * Closes a opened edit
 */
- (void)endEditListAtTime:(CMTime)time empty:(BOOL)type helper:(AVFDemuxHelper *)helper {
    if (!helper->editOpen)
        return;

    time.value -= helper->edits[helper->editsCount].start.value;
    helper->edits[helper->editsCount].duration = time;

    if (type) {
        helper->edits[helper->editsCount].start.value = -1;
    }

    helper->editsCount++;
    helper->editOpen = NO;
}

//#define SB_AVF_DEBUG

- (void)demux:(id)sender {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	BOOL success = YES;
    OSStatus err = noErr;

    uint64_t currentDataLength = 0;
    uint64_t totalDataLength = 0;

    AVFDemuxHelper *demuxHelper=nil;
    NSError *localError;
    AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:_localAsset error:&localError];

	success = (assetReader != nil);
	if (success) {
        for (MP42Track * track in _inputTracks) {
            AVAssetReaderOutput *assetReaderOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[_localAsset trackWithTrackID:track.sourceId] outputSettings:nil];
            if (! [assetReader canAddOutput: assetReaderOutput])
                NSLog(@"Unable to add the output to assetReader!");

            [assetReader addOutput:assetReaderOutput];

            track.muxer_helper->demuxer_context = [[AVFDemuxHelper alloc] init];
            demuxHelper = track.muxer_helper->demuxer_context;
            demuxHelper->assetReaderOutput = assetReaderOutput;

            totalDataLength += [track dataLength];
        }
    }

    success = [assetReader startReading];
	if (!success)
		localError = [assetReader error];

    for (MP42Track *track in _inputTracks) {
        demuxHelper = track.muxer_helper->demuxer_context;
        AVAssetReaderOutput *assetReaderOutput = demuxHelper->assetReaderOutput;
        int32_t timescale = 0;

        [self startEditListAtTime:kCMTimeInvalid helper:demuxHelper];

        while (!_cancelled) {
            CMSampleBufferRef sampleBuffer = [assetReaderOutput copyNextSampleBuffer];
            if (sampleBuffer) {
                CMItemCount samplesNum = CMSampleBufferGetNumSamples(sampleBuffer);
                if (samplesNum == 1) {
                    // We have only a sample
                    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
                    CMTime decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
                    CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                    CMTime presentationOutputTimeStamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);

                    CMBlockBufferRef buffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                    size_t sampleSize = CMBlockBufferGetDataLength(buffer);
                    void *sampleData = malloc(sampleSize);
                    CMBlockBufferCopyDataBytes(buffer, 0, sampleSize, sampleData);

                    // Read sample attachment, sync to mark the frame as sync
                    BOOL sync = 1;
                    CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, NO);
                    if (attachmentsArray) {
                        for (NSDictionary *dict in (NSArray *)attachmentsArray) {
                            if ([dict valueForKey:(NSString *)kCMSampleAttachmentKey_NotSync])
                                sync = 0;
                        }
                    }

                    if (timescale == 0) {
                        timescale = duration.timescale;
                    }

                    // Check for the initial empty edit
                    if (demuxHelper->currentTime == 0 && presentationOutputTimeStamp.value != 0) {
                        CMTime time = CMTimeConvertScale(presentationOutputTimeStamp, duration.timescale, kCMTimeRoundingMethod_Default);
                        [self endEditListAtTime:time empty:YES helper:demuxHelper];
                        [self startEditListAtTime:time helper:demuxHelper];
                        demuxHelper->currentTime += time.value;
                    }

#ifdef SB_AVF_DEBUG
                    NSLog(@"Dur: %lld, D: %lld, P: %lld, PO: %lld", duration.value, decodeTimeStamp.value, presentationTimeStamp.value, presentationOutputTimeStamp.value);
#endif

                    // Check if we have to trim the start or end of a sample
                    // If so it means we need to start/end an edit
                    CFTypeRef trimStart = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_TrimDurationAtStart, kCMAttachmentMode_ShouldNotPropagate);
                    if (trimStart) {
                        CMTime trimStartTime = CMTimeMakeFromDictionary(trimStart);

                        trimStartTime = CMTimeConvertScale(trimStartTime, duration.timescale, kCMTimeRoundingMethod_Default);
                        CMTime editStart = CMTimeMake(demuxHelper->currentTime, duration.timescale);
                        editStart.value += trimStartTime.value;

                        [self startEditListAtTime:editStart helper:demuxHelper];
                    }
                    CFTypeRef trimEnd = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_TrimDurationAtEnd, kCMAttachmentMode_ShouldNotPropagate);
                    if (trimEnd) {
                        CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);

                        trimEndTime = CMTimeConvertScale(trimEndTime, duration.timescale, kCMTimeRoundingMethod_Default);
                        CMTime editEnd = CMTimeMake(demuxHelper->currentTime, duration.timescale);
                        editEnd.value += duration.value - trimEndTime.value;

                        [self endEditListAtTime:editEnd empty:NO helper:demuxHelper];
                    }

                    // Enqueues the new sample
                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->data = sampleData;
                    sample->size = sampleSize;
                    sample->duration = duration.value;
                    sample->offset = -decodeTimeStamp.value + presentationTimeStamp.value;
                    sample->timestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer).value;
                    sample->isSync = sync;
                    sample->trackId = track.sourceId;

                    [self enqueue:sample];
                    [sample release];

                    demuxHelper->currentTime += duration.value;
                    currentDataLength += sampleSize;
                } else {
                    // The CMSampleBufferRef contains more than one sample
                    if (!CMSampleBufferDataIsReady(sampleBuffer))
                        CMSampleBufferMakeDataReady(sampleBuffer);

                    // A CMSampleBufferRef can contains an unknown number of samples, check how many needs to be divided to separated MP42SampleBuffers
                    // First get the array with the timings for each sample
                    CMItemCount timingArrayEntries = 0;
                    CMItemCount timingArrayEntriesNeededOut = 0;
                    err = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, timingArrayEntries, NULL, &timingArrayEntriesNeededOut);
                    if (err)
                        continue;

                    CMSampleTimingInfo *timingArrayOut = malloc(sizeof(CMSampleTimingInfo) * timingArrayEntriesNeededOut);
                    timingArrayEntries = timingArrayEntriesNeededOut;
                    err = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, timingArrayEntries, timingArrayOut, &timingArrayEntriesNeededOut);
                    if (err)
                        continue;

                    // Then the array with the size of each sample
                    CMItemCount sizeArrayEntries = 0;
                    CMItemCount sizeArrayEntriesNeededOut = 0;
                    err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, NULL, &sizeArrayEntriesNeededOut);
                    if (err)
                        continue;

                    size_t *sizeArrayOut = malloc(sizeof(size_t) * sizeArrayEntriesNeededOut);
                    sizeArrayEntries = sizeArrayEntriesNeededOut;
                    err = CMSampleBufferGetSampleSizeArray(sampleBuffer, sizeArrayEntries, sizeArrayOut, &sizeArrayEntriesNeededOut);
                    if (err)
                        continue;

                    // Get CMBlockBufferRef to extract the actual data later
                    CMBlockBufferRef buffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                    size_t bufferSize = CMBlockBufferGetDataLength(buffer);

#ifdef SB_AVF_DEBUG
#endif

                    // Check if we have to trim the start or end of a sample
                    // If so it means we need to start/end an edit
                    CFTypeRef trimStart = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_TrimDurationAtStart, kCMAttachmentMode_ShouldNotPropagate);
                    if (trimStart) {
                        CMTime trimStartTime = CMTimeMakeFromDictionary(trimStart);
                        trimStartTime = CMTimeConvertScale(trimStartTime, timingArrayOut[0].duration.timescale, kCMTimeRoundingMethod_Default);

                        CMTime editStart = CMTimeMake(demuxHelper->currentTime, timingArrayOut[0].duration.timescale);
                        editStart.value += trimStartTime.value;

                        [self startEditListAtTime:editStart helper:demuxHelper];
                    }
                    CFTypeRef trimEnd = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_TrimDurationAtEnd, kCMAttachmentMode_ShouldNotPropagate);
                    if (trimEnd) {
                        CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
                        trimEndTime = CMTimeConvertScale(trimEndTime, timingArrayOut[0].duration.timescale, kCMTimeRoundingMethod_Default);

                        CMTime editEnd = CMTimeMake(demuxHelper->currentTime, timingArrayOut[0].duration.timescale);
                        editEnd.value += timingArrayOut[0].duration.value * samplesNum  - trimEndTime.value;

                        [self endEditListAtTime:editEnd empty:NO helper:demuxHelper];

                    }

                    if (timescale == 0) {
                        timescale = timingArrayOut[0].duration.timescale;
                    }

                    int pos = 0;
                    for (int i = 0; i < samplesNum; i++) {
                        CMSampleTimingInfo sampleTimingInfo;
                        CMTime decodeTimeStamp;
                        CMTime presentationTimeStamp;
                        CMTime presentationOutputTimeStamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);

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

                        presentationOutputTimeStamp.value = presentationOutputTimeStamp.value + (sampleTimingInfo.duration.value * i /
                                                                                                 ((double) sampleTimingInfo.duration.timescale / presentationOutputTimeStamp.timescale));

                        // If the size of sample size array is equal to 1, it means every sample has got the same size
                        if (sizeArrayEntries ==  1) {
                            sampleSize = sizeArrayOut[0];
                        } else {
                            sampleSize = sizeArrayOut[i];
                        }

                        if (!sampleSize)
                            continue;

                        void *sampleData = malloc(sampleSize);

                        if (pos < bufferSize) {
                            CMBlockBufferCopyDataBytes(buffer, pos, sampleSize, sampleData);
                            pos += sampleSize;
                        }

                        // Read sample attachment, sync to mark the frame as sync
                        BOOL sync = 1;
                        CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, NO);
                        if (attachmentsArray) {
                            for (NSDictionary *dict in (NSArray *)attachmentsArray) {
                                if ([dict valueForKey:(NSString *)kCMSampleAttachmentKey_NotSync])
                                    sync = 0;
                            }
                        }

#ifdef SB_AVF_DEBUG
                        NSLog(@"D: %lld, P: %lld, PO: %lld", decodeTimeStamp.value, presentationTimeStamp.value, presentationOutputTimeStamp.value);
#endif

                        // Enqueues the new sample
                        MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                        sample->data = sampleData;
                        sample->size = sampleSize;
                        sample->duration = sampleTimingInfo.duration.value;
                        sample->offset = -decodeTimeStamp.value + presentationTimeStamp.value;
                        sample->timestamp = sampleTimingInfo.presentationTimeStamp.value;
                        sample->isSync = sync;
                        sample->trackId = track.sourceId;

                        [self enqueue:sample];
                        [sample release];

                        demuxHelper->currentTime += sampleTimingInfo.duration.value;
                        currentDataLength += sampleSize;
                    }

                    if (timingArrayOut)
                        free(timingArrayOut);
                    if (sizeArrayOut)
                        free(sizeArrayOut);
                }
                CFRelease(sampleBuffer);

                _progress = (((CGFloat) currentDataLength /  totalDataLength ) * 100);

            } else {
                break;
            }
        }
        // Closes the last edit
        [self endEditListAtTime:CMTimeMake(demuxHelper->currentTime, timescale) empty:NO helper:demuxHelper];
    }

    [assetReader release];
    [self setDone:YES];
    [pool release];
}

- (void)startReading {
    [super startReading];

    if (!_demuxerThread && !_done) {
        _demuxerThread = [[NSThread alloc] initWithTarget:self selector:@selector(demux:) object:self];
        [_demuxerThread setName:@"AVFoundation Demuxer"];
        [_demuxerThread start];
    }
}

- (BOOL)cleanUp:(MP4FileHandle)fileHandle {
    uint32_t timescale = MP4GetTimeScale(fileHandle);

    for (MP42Track *track in _inputTracks) {
        MP4Duration trackDuration = 0;
        MP42Track *inputTrack = [self inputTrackWithTrackID:track.sourceId];

        AVFDemuxHelper *demuxHelper = inputTrack.muxer_helper->demuxer_context;

        for (int i = 0; i < demuxHelper->editsCount; i++) {
            CMTimeRange timeRange = demuxHelper->edits[i];
            CMTime duration = CMTimeConvertScale(timeRange.duration, timescale, kCMTimeRoundingMethod_Default);

            trackDuration += duration.value;

            MP4AddTrackEdit(fileHandle, track.Id, MP4_INVALID_EDIT_ID, timeRange.start.value,
                            duration.value, 0);

#ifdef SB_AVF_DEBUG
            NSLog(@"Edit start: %lld, duration: %lld", timeRange.start.value, duration.value);
#endif
        }

        if (trackDuration)
            MP4SetTrackIntegerProperty(fileHandle, track.Id, "tkhd.duration", trackDuration);

        free(demuxHelper->edits);

    }
    return YES;
}

- (void) dealloc {
    [_localAsset release];
    [super dealloc];
}

@end

#endif
