//
//  MP42Muxer.m
//  Subler
//
//  Created by Damiano Galassi on 30/06/10.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42Muxer.h"

#import "MP42File.h"
#import "MP42FileImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42SampleBuffer.h"
#import "MP42AudioConverter.h"
#import "MP42BitmapSubConverter.h"
#import "MP42TextSubConverter.h"

#import "mp4v2.h"
#import "MP42FormatUtilites.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Private.h"

#include <stdatomic.h>

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42Muxer
{
    MP4FileHandle    _fileHandle;

    id <MP42MuxerDelegate>  _delegate;
    id <MP42Logging>        _logger;

    NSMutableArray<MP42Track *> *_activeTracks;
    NSDictionary<NSString *, id> *_options;

    dispatch_semaphore_t _setupDone;
    int32_t              _cancelled;
    _Atomic bool      _readingCancelled;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _activeTracks = [[NSMutableArray alloc] init];
    }
    return self;
}

- (instancetype)initWithFileHandle:(MP4FileHandle)fileHandle delegate:(id <MP42MuxerDelegate>)del logger:(id <MP42Logging>)logger options:(nullable NSDictionary<NSString *, id> *)options
{
    if ((self = [self init])) {
        NSParameterAssert(fileHandle);
        _fileHandle = fileHandle;
        _delegate = del;
        _logger = logger;
        _options = [options copy];
        _setupDone = dispatch_semaphore_create(0);
    }

    return self;
}

- (BOOL)canAddTrack:(MP42Track *)track
{
    if (isTrackMuxable(track.targetFormat)) {
        if ([track isMemberOfClass:[MP42AudioTrack class]]) {
            // TO-DO Check if we can initialize the audio converter
        }
        return YES;
    } else {
        return NO;
    }
}

- (void)addTrack:(MP42Track *)track
{
    if (![track isMemberOfClass:[MP42ChapterTrack class]]) {
        [_activeTracks addObject:track];
    }
}

- (BOOL)setup:(NSError * __autoreleasing *)outError
{
    NSMutableArray<MP42Track *> *unsupportedTracks = [[NSMutableArray alloc] init];

    for (MP42FileImporter *importer in self.fileImporters) {
        [importer setup];
    }

    for (MP42Track *track in _activeTracks) {

        MP42FileImporter *importer = track.importer;
        FourCharCode format = track.format;
        MP4TrackId dstTrackId = 0;
        NSData *magicCookie = nil;
        uint32_t timeScale = track.timescale;

        if (importer) {
            magicCookie = [importer magicCookieForTrack:track];
        } else {
            [unsupportedTracks addObject:track];
            continue;
        }

        // Setup the converters
        if ([track isMemberOfClass:[MP42AudioTrack class]] && track.conversionSettings) {
            MP42AudioConverter *audioConverter = [[MP42AudioConverter alloc] initWithTrack:(MP42AudioTrack *)track
                                                                                  settings:(MP42AudioConversionSettings *)track.conversionSettings
                                                                                     error:outError];

            if (audioConverter == nil) {
                if (outError && *outError) {
                    [_logger writeErrorToLog:*outError];
                }
                [unsupportedTracks addObject:track];
                continue;
            }

            track.converter = audioConverter;
            // The audio converter might downsample the audio,
            // so update the track timescale here.
            timeScale = audioConverter.sampleRate;
            format = track.conversionSettings.format;
        }
        if ([track isMemberOfClass:[MP42SubtitleTrack class]] && track.conversionSettings &&
                (track.format == kMP42SubtitleCodecType_VobSub || track.format == kMP42SubtitleCodecType_PGS)) {
            MP42BitmapSubConverter *subConverter = [[MP42BitmapSubConverter alloc] initWithTrack:(MP42SubtitleTrack *)track
                                                                                       error:outError];

            if (subConverter == nil) {
                if (outError && *outError) {
                    [_logger writeErrorToLog:*outError];
                }
                [unsupportedTracks addObject:track];
                continue;
            }

            track.converter = subConverter;
            format = track.conversionSettings.format;
        } else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && track.conversionSettings) {
            MP42TextSubConverter *subConverter = [[MP42TextSubConverter alloc] initWithTrack:(MP42SubtitleTrack *)track
                                                                                           error:outError];

            if (subConverter == nil) {
                if (outError && *outError) {
                    [_logger writeErrorToLog:*outError];
                }
                [unsupportedTracks addObject:track];
                continue;
            }

            track.converter = subConverter;
            format = track.conversionSettings.format;
        }

        // H.264 video track
        if ([track isMemberOfClass:[MP42VideoTrack class]] && format == kMP42VideoCodecType_H264) {

            if (magicCookie.length < sizeof(uint8_t) * 6) {
                [unsupportedTracks addObject:track];
                continue;
            }

            uint8_t *avcCAtom = (uint8_t *)magicCookie.bytes;
            dstTrackId = MP4AddH264VideoTrack(_fileHandle, timeScale,
                                              MP4_INVALID_DURATION,
                                              ((MP42VideoTrack *)track).width, ((MP42VideoTrack *)track).height,
                                              avcCAtom[1],  // AVCProfileIndication
                                              avcCAtom[2],  // profile_compat
                                              avcCAtom[3],  // AVCLevelIndication
                                              avcCAtom[4]); // lengthSizeMinusOne

            SInt64 i;
            int8_t spsCount = (avcCAtom[5] & 0x1f);
            uint8_t ptrPos = 6;
            NSUInteger len = magicCookie.length;
            for (i = 0; i < spsCount; i++) {
                uint16_t spsSize = (avcCAtom[ptrPos++] << 8) & 0xff00;
                spsSize += avcCAtom[ptrPos++] & 0xff;

                if (ptrPos + spsSize <= len) {
                    MP4AddH264SequenceParameterSet(_fileHandle, dstTrackId,
                                                   avcCAtom + ptrPos, spsSize);
                    ptrPos += spsSize;
                } else {
                    break;
                }
            }

            int8_t ppsCount = avcCAtom[ptrPos++];
            for (i = 0; i < ppsCount; i++) {
                uint16_t ppsSize = (avcCAtom[ptrPos++] << 8) & 0xff00;
                ppsSize += avcCAtom[ptrPos++] & 0xff;

                if (ptrPos + ppsSize <= len) {
                    MP4AddH264PictureParameterSet(_fileHandle, dstTrackId,
                                                  avcCAtom + ptrPos, ppsSize);
                    ptrPos += ppsSize;

                } else {
                    break;
                }
            }

            MP4SetVideoProfileLevel(_fileHandle, 0x15);

            [importer setActiveTrack:track];
        }

        // H.265 video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] &&
                 (format == kMP42VideoCodecType_HEVC || format == kMP42VideoCodecType_HEVC_PSinBitstream)) {

            MP42VideoTrack *videoTrack = (MP42VideoTrack *)track;
            uint8_t *hvcCAtom = (uint8_t *)magicCookie.bytes;

            if ([_options[MP42ForceHvc1] boolValue] && magicCookie.length < UINT32_MAX) {
                force_HEVC_completeness(hvcCAtom, (uint32_t)magicCookie.length);
            }

            // Check whether we can use hvc1 or hev1 fourcc.
            bool completeness = 0;
            if (magicCookie.length && magicCookie.length < UINT32_MAX && !analyze_HEVC(magicCookie.bytes, (uint32_t)magicCookie.length, &completeness)) {

                dstTrackId = MP4AddH265VideoTrack(_fileHandle, timeScale, MP4_INVALID_DURATION,
                                                  videoTrack.width, videoTrack.height,
                                                  magicCookie.bytes, (uint32_t)magicCookie.length,
                                                  completeness);

                if (dstTrackId) {
                    if (videoTrack.dolbyVision.versionMajor > 0) {
                        MP4SetDolbyVisionMetadata(_fileHandle, dstTrackId,
                                                  videoTrack.dolbyVision.versionMajor,
                                                  videoTrack.dolbyVision.versionMinor,
                                                  videoTrack.dolbyVision.profile,
                                                  videoTrack.dolbyVision.level,
                                                  videoTrack.dolbyVision.rpuPresentFlag,
                                                  videoTrack.dolbyVision.elPresentFlag,
                                                  videoTrack.dolbyVision.blPresentFlag,
                                                  videoTrack.dolbyVision.blSignalCompatibilityId);
                    }
                    if (videoTrack.dolbyVisionELConfiguration) {
                        MP4SetDolbyVisionELConfiguration(_fileHandle, dstTrackId,
                                                         videoTrack.dolbyVisionELConfiguration.bytes,
                                                         (uint32_t)videoTrack.dolbyVisionELConfiguration.length);
                    }
                    [importer setActiveTrack:track];
                }
                else {
                    [unsupportedTracks addObject:track];
                    continue;
                }
            }
            else {
                [unsupportedTracks addObject:track];
                continue;
            }
        }

        // Dolby Vision H.265 video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] &&
                 (format == kMP42VideoCodecType_DolbyVisionHEVC || format == kMP42VideoCodecType_DolbyVisionHEVC_PSinBitstream)) {

            MP42VideoTrack *videoTrack = (MP42VideoTrack *)track;
            uint8_t *hvcCAtom = (uint8_t *)magicCookie.bytes;

            if ([_options[MP42ForceHvc1] boolValue] && magicCookie.length < UINT32_MAX) {
                force_HEVC_completeness(hvcCAtom, (uint32_t)magicCookie.length);
            }

            bool completeness = false;
            if (magicCookie.length && magicCookie.length < UINT32_MAX && !analyze_HEVC(magicCookie.bytes, (uint32_t)magicCookie.length, &completeness)) {

                dstTrackId = MP4AddDolbyVisionH265VideoTrack(_fileHandle, timeScale, MP4_INVALID_DURATION,
                                                             videoTrack.width, videoTrack.height,
                                                             magicCookie.bytes, (uint32_t)magicCookie.length,
                                                             videoTrack.dolbyVision.versionMajor,
                                                             videoTrack.dolbyVision.versionMinor,
                                                             videoTrack.dolbyVision.profile,
                                                             videoTrack.dolbyVision.level,
                                                             videoTrack.dolbyVision.rpuPresentFlag,
                                                             videoTrack.dolbyVision.elPresentFlag,
                                                             videoTrack.dolbyVision.blPresentFlag,
                                                             videoTrack.dolbyVision.blSignalCompatibilityId,
                                                             completeness);

                if (dstTrackId) {
                    if (videoTrack.dolbyVisionELConfiguration) {
                        MP4SetDolbyVisionELConfiguration(_fileHandle, dstTrackId,
                                                         videoTrack.dolbyVisionELConfiguration.bytes,
                                                         (uint32_t)videoTrack.dolbyVisionELConfiguration.length);
                    }
                    [importer setActiveTrack:track];
                }
                else {
                    [unsupportedTracks addObject:track];
                    continue;
                }
            }
            else {
                [unsupportedTracks addObject:track];
                continue;
            }
        }

        // H.266 video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] &&
                 (format == kMP42VideoCodecType_VVC || format == kMP42VideoCodecType_VVC_PSinBitstream)) {

            MP42VideoTrack *videoTrack = (MP42VideoTrack *)track;
//            uint8_t *vvcCAtom = (uint8_t *)magicCookie.bytes;

//            if ([_options[MP42ForceHvc1] boolValue] && magicCookie.length < UINT32_MAX) {
//                force_HEVC_completeness(hvcCAtom, (uint32_t)magicCookie.length);
//            }

            // Check whether we can use hvc1 or hev1 fourcc.
            bool completeness = true;
            if (magicCookie.length && magicCookie.length < UINT32_MAX && !analyze_HEVC(magicCookie.bytes, (uint32_t)magicCookie.length, &completeness)) {

                dstTrackId = MP4AddVVCVideoTrack(_fileHandle, timeScale, MP4_INVALID_DURATION,
                                                 videoTrack.width, videoTrack.height,
                                                 magicCookie.bytes, (uint32_t)magicCookie.length,
                                                 completeness);

                if (dstTrackId) {
                    if (videoTrack.dolbyVision.versionMajor > 0) {
                        MP4SetDolbyVisionMetadata(_fileHandle, dstTrackId,
                                                  videoTrack.dolbyVision.versionMajor,
                                                  videoTrack.dolbyVision.versionMinor,
                                                  videoTrack.dolbyVision.profile,
                                                  videoTrack.dolbyVision.level,
                                                  videoTrack.dolbyVision.rpuPresentFlag,
                                                  videoTrack.dolbyVision.elPresentFlag,
                                                  videoTrack.dolbyVision.blPresentFlag,
                                                  videoTrack.dolbyVision.blSignalCompatibilityId);
                    }
                    if (videoTrack.dolbyVisionELConfiguration) {
                        MP4SetDolbyVisionELConfiguration(_fileHandle, dstTrackId,
                                                         videoTrack.dolbyVisionELConfiguration.bytes,
                                                         (uint32_t)videoTrack.dolbyVisionELConfiguration.length);
                    }
                    [importer setActiveTrack:track];
                }
                else {
                    [unsupportedTracks addObject:track];
                    continue;
                }
            }
            else {
                [unsupportedTracks addObject:track];
                continue;
            }
        }

        // AV1 video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] && (format == kMP42VideoCodecType_AV1)) {
            MP42VideoTrack *videoTrack = (MP42VideoTrack *)track;
            if (magicCookie.length && magicCookie.length < UINT32_MAX) {

                dstTrackId = MP4AddAV1VideoTrack(_fileHandle, timeScale, MP4_INVALID_DURATION,
                                                  videoTrack.width, videoTrack.height,
                                                 magicCookie.bytes, (uint32_t)magicCookie.length);

                if (dstTrackId) {
                    if (videoTrack.dolbyVision.versionMajor > 0) {
                        MP4SetDolbyVisionMetadata(_fileHandle, dstTrackId,
                                                  videoTrack.dolbyVision.versionMajor,
                                                  videoTrack.dolbyVision.versionMinor,
                                                  videoTrack.dolbyVision.profile,
                                                  videoTrack.dolbyVision.level,
                                                  videoTrack.dolbyVision.rpuPresentFlag,
                                                  videoTrack.dolbyVision.elPresentFlag,
                                                  videoTrack.dolbyVision.blPresentFlag,
                                                  videoTrack.dolbyVision.blSignalCompatibilityId);
                    }
                    if (videoTrack.dolbyVisionELConfiguration) {
                        MP4SetDolbyVisionELConfiguration(_fileHandle, dstTrackId,
                                                         videoTrack.dolbyVisionELConfiguration.bytes,
                                                         (uint32_t)videoTrack.dolbyVisionELConfiguration.length);
                    }
                    [importer setActiveTrack:track];
                }
                else {
                    [unsupportedTracks addObject:track];
                    continue;
                }
            }
            else {
                [unsupportedTracks addObject:track];
                continue;
            }
        }


        // MPEG-4 Visual video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] && format == kMP42VideoCodecType_MPEG4Video) {
            MP4SetVideoProfileLevel(_fileHandle, MPEG4_SP_L3);
            // Add video track
            dstTrackId = MP4AddVideoTrack(_fileHandle, timeScale,
                                          MP4_INVALID_DURATION,
                                          [(MP42VideoTrack*)track width], [(MP42VideoTrack*)track height],
                                          MP4_MPEG4_VIDEO_TYPE);

            if (magicCookie.length && magicCookie.length < UINT32_MAX) {
                MP4SetTrackESConfiguration(_fileHandle, dstTrackId,
                                           magicCookie.bytes,
                                           (uint32_t)magicCookie.length);
            }

            [importer setActiveTrack:track];
        }

        // Photo-JPEG video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] && format == kMP42VideoCodecType_JPEG) {
            // Add video track
            dstTrackId = MP4AddJpegVideoTrack(_fileHandle, timeScale,
                                  MP4_INVALID_DURATION, [(MP42VideoTrack*)track width], [(MP42VideoTrack*)track height]);

            [importer setActiveTrack:track];
        }

        // AAC audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] &&
                 (format == kMP42AudioCodecType_MPEG4AAC || format == kMP42AudioCodecType_MPEG4AAC_HE)) {

            dstTrackId = MP4AddAudioTrack(_fileHandle,
                                          timeScale,
                                          1024, MP4_MPEG4_AUDIO_TYPE);

            if (!track.conversionSettings && magicCookie.length && magicCookie.length < UINT32_MAX) {
                MP4SetTrackESConfiguration(_fileHandle, dstTrackId,
                                           magicCookie.bytes,
                                           (uint32_t)magicCookie.length);
            }

            MP4SetTrackWantsRoll(_fileHandle, dstTrackId, [importer audioTrackUsesExplicitEncoderDelay:track]);

            [importer setActiveTrack:track];
        }

        // AC-3 audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && format == kMP42AudioCodecType_AC3) {
            if (magicCookie.length < sizeof(uint64_t) * 6) {

                dstTrackId = MP4AddAC3AudioTrack(_fileHandle,
                                                 timeScale,
                                                 0,
                                                 0,
                                                 0,
                                                 0,
                                                 0,
                                                 0);
            }
            else {
                const uint64_t *ac3Info = (const uint64_t *)magicCookie.bytes;

                dstTrackId = MP4AddAC3AudioTrack(_fileHandle,
                                                 timeScale,
                                                 ac3Info[0],
                                                 ac3Info[1],
                                                 ac3Info[2],
                                                 ac3Info[3],
                                                 ac3Info[4],
                                                 ac3Info[5]);
            }

            [importer setActiveTrack:track];
        }

        // EAC-3 audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && format == kMP42AudioCodecType_EnhancedAC3) {
            dstTrackId = MP4AddEAC3AudioTrack(_fileHandle, timeScale, magicCookie.bytes, magicCookie.length);

            [importer setActiveTrack:track];
        }

        // ALAC audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && format == kMP42AudioCodecType_AppleLossless) {
            dstTrackId = MP4AddALACAudioTrack(_fileHandle,
                                          timeScale);
            if (magicCookie.length && magicCookie.length < UINT32_MAX) {
                MP4SetTrackBytesProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.alac.alac.AppleLosslessMagicCookie",
                                         magicCookie.bytes, (uint32_t)magicCookie.length);
            }

            [importer setActiveTrack:track];
        }

        // DTS audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && format == kMP42AudioCodecType_DTS) {
            dstTrackId = MP4AddAudioTrack(_fileHandle,
                                          timeScale,
                                          512, 0xA9);

            [importer setActiveTrack:track];
        }

        // 3GPP text track
        else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && format == kMP42SubtitleCodecType_3GText) {
            NSSize subSize = NSMakeSize(0, 0);
            NSSize videoSize = NSMakeSize(0, 0);

            MP42SubtitleTrack *subTrack = (MP42SubtitleTrack *)track;
            NSInteger vPlacement = subTrack.verticalPlacement;

            for (id workingTrack in _activeTracks) {
                if ([workingTrack isMemberOfClass:[MP42VideoTrack class]]) {
                    videoSize.width  = [workingTrack trackWidth];
                    videoSize.height = [workingTrack trackHeight];
                    break;
                }
            }

            if (!videoSize.width) {
                MP4TrackId videoTrack = findFirstVideoTrack(_fileHandle);
                if (videoTrack) {
                    videoSize.width = getFixedVideoWidth(_fileHandle, videoTrack);
                    videoSize.height = MP4GetTrackVideoHeight(_fileHandle, videoTrack);
                }
                else {
                    videoSize.width = 640;
                    videoSize.height = 480;
                }
            }
            if (!vPlacement) {
                if (subTrack.trackHeight)
                    subSize.height = subTrack.trackHeight;
                else
                    subSize.height = 0.15 * videoSize.height;
            }
            else {
                subSize.height = videoSize.height;
            }

            const uint8_t textColor[4] = { 255,255,255,255 };
            dstTrackId = MP4AddSubtitleTrack(_fileHandle, timeScale, videoSize.width, subSize.height);

            MP4SetTrackDurationPerChunk(_fileHandle, dstTrackId, timeScale / 8);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "tkhd.layer", -1);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.horizontalJustification", 1);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.verticalJustification", -1);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorRed", 0);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorGreen", 0);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorBlue", 0);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorAlpha", 0);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontSize", videoSize.height * 0.05);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorRed", textColor[0]);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorGreen", textColor[1]);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorBlue", textColor[2]);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorAlpha", textColor[3]);

            /* translate the track */
            if (!vPlacement) {
                CGAffineTransform transform = subTrack.transform;
                transform.ty = videoSize.height * 0.85;
                subTrack.transform = transform;
            }

            subTrack.trackWidth = videoSize.width;
            subTrack.trackHeight = subSize.height;

            [importer setActiveTrack:track];
        }

        // VobSub bitmap track
        else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && format == kMP42SubtitleCodecType_VobSub) {
            if (magicCookie.length < sizeof(uint32_t) * 16) {
                [unsupportedTracks addObject:track];
                continue;
            }

            dstTrackId = MP4AddSubpicTrack(_fileHandle, timeScale, 640, 480);

            uint32_t *subPalette = (uint32_t *) magicCookie.bytes;
            for (int ii = 0; ii < 16; ii++) {
                subPalette[ii] = rgb2yuv(subPalette[ii]);
            }

            uint8_t palette[16][4];
            for (int ii = 0; ii < 16; ii++ ) {
                palette[ii][0] = 0;
                palette[ii][1] = (subPalette[ii] >> 16) & 0xff;
                palette[ii][2] = (subPalette[ii] >> 8) & 0xff;
                palette[ii][3] = (subPalette[ii]) & 0xff;
            }
            MP4SetTrackESConfiguration(_fileHandle, dstTrackId,
                                             (uint8_t *)palette, 16 * 4 );

            [importer setActiveTrack:track];
        }

        // WebVTT
        else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && format ==kMP42SubtitleCodecType_WebVTT) {
            NSSize videoSize = NSMakeSize(((MP42VideoTrack *)track).width, ((MP42VideoTrack *)track).height);

            for (id workingTrack in _activeTracks)
                if ([workingTrack isMemberOfClass:[MP42VideoTrack class]]) {
                    videoSize.width  = [workingTrack trackWidth];
                    videoSize.height = [workingTrack trackHeight];
                    break;
                }

            if (!videoSize.width) {
                MP4TrackId videoTrack = findFirstVideoTrack(_fileHandle);
                if (videoTrack) {
                    videoSize.width = getFixedVideoWidth(_fileHandle, videoTrack);
                    videoSize.height = MP4GetTrackVideoHeight(_fileHandle, videoTrack);
                }
                else {
                    videoSize.width = 640;
                    videoSize.height = 480;
                }
            }

            dstTrackId = MP4AddWebVTTTrack(_fileHandle, timeScale, videoSize.width, videoSize.height, magicCookie.bytes, magicCookie.length);

            [importer setActiveTrack:track];
        }

        // Closed Caption text track
        else if ([track isMemberOfClass:[MP42ClosedCaptionTrack class]]) {
            NSSize videoSize = NSMakeSize(((MP42VideoTrack *)track).width, ((MP42VideoTrack *)track).height);

            for (id workingTrack in _activeTracks)
                if ([workingTrack isMemberOfClass:[MP42VideoTrack class]]) {
                    videoSize.width  = [workingTrack trackWidth];
                    videoSize.height = [workingTrack trackHeight];
                    break;
                }

            if (!videoSize.width) {
                MP4TrackId videoTrack = findFirstVideoTrack(_fileHandle);
                if (videoTrack) {
                    videoSize.width = getFixedVideoWidth(_fileHandle, videoTrack);
                    videoSize.height = MP4GetTrackVideoHeight(_fileHandle, videoTrack);
                }
                if (videoSize.width == 0 || videoSize.height == 0) {
                    videoSize.width = 640;
                    videoSize.height = 480;
                }
            }

            dstTrackId = MP4AddCCTrack(_fileHandle, timeScale, videoSize.width, videoSize.height);

            [importer setActiveTrack:track];
        } else {
            [unsupportedTracks addObject:track];
            continue;
        }

        if (dstTrackId) {
            MP4SetTrackDurationPerChunk(_fileHandle, dstTrackId, timeScale / 8);
            track.trackId = dstTrackId;
        }
    }

    [_activeTracks removeObjectsInArray:unsupportedTracks];

    dispatch_semaphore_signal(_setupDone);

    return YES;
}

- (void)work
{
    if (!_activeTracks.count) {
        return;
    }

    NSArray<MP42FileImporter *> *trackImportersArray = self.fileImporters;
    NSUInteger done = 0, update = 0;
    CGFloat progress = 0;

    for (MP42FileImporter *importerHelper in trackImportersArray) {
        [importerHelper startReading];
    }

    NSUInteger tracksImportersCount = trackImportersArray.count;
    NSUInteger tracksCount = _activeTracks.count;
    NSMutableArray<MP42Track *> *tracks = [_activeTracks copy];
    NSMutableArray<MP42Track *> *nextTracks = nil;

    for (;;) {
        @autoreleasepool {

            usleep(1000);

            if (nextTracks) {
                tracks = nextTracks;
                nextTracks = nil;
            }

            // Iterate the tracks array and mux the samples
            for (MP42Track *track in tracks) {
                MP42SampleBuffer *sampleBuffer = nil;
                MP42TrackId trackId = track.trackId;

                for (int i = 0; i < 100 && (sampleBuffer = [track copyNextSample]) != nil; i++) {

                    if (sampleBuffer->flags & MP42SampleBufferFlagEndOfFile) {
                        // Tracks done, remove it from the loop
                        nextTracks = nextTracks != nil ? nextTracks : [tracks mutableCopy];
                        [nextTracks removeObject:track];
                        done += 1;
                        break;
                    }
                    else {
                        bool err = false;
                        if (sampleBuffer->dependecyFlags) {
                            err = MP4WriteSampleDependency(_fileHandle, trackId, sampleBuffer->data, sampleBuffer->size,
                                                           sampleBuffer->duration, sampleBuffer->offset,
                                                           (sampleBuffer->flags & MP42SampleBufferFlagIsSync) != 0,
                                                           sampleBuffer->dependecyFlags);
                        } else {
                            err = MP4WriteSample(_fileHandle, trackId,
                                                 sampleBuffer->data, sampleBuffer->size,
                                                 sampleBuffer->duration, sampleBuffer->offset,
                                                 (sampleBuffer->flags & MP42SampleBufferFlagIsSync) != 0);
                        }
                        if (!err) {
                            _cancelled = YES;
                        }
                    }
                }
            }

            if (_cancelled) {
                break;
            }

            // If all tracks are done, exit the loop
            if (done == tracksCount) {
                break;
            }

            // Update progress
            if (!(update % 200)) {
                progress = 0;
                for (MP42FileImporter *importerHelper in trackImportersArray) {
                    progress += importerHelper.progress;
                }

                progress /= tracksImportersCount;

                [_delegate progressStatus:progress];
            }
            update++;
        }
    }

    // Write the converted audio track magic cookie
    for (MP42Track *track in _activeTracks) {
        if (track.converter && track.conversionSettings && [track isMemberOfClass:[MP42AudioTrack class]]) {
            NSData *magicCookie = track.converter.magicCookie;

            if (magicCookie && magicCookie.length < UINT32_MAX) {
                if (track.conversionSettings.format == kAudioFormatMPEG4AAC) {
                    MP4SetTrackESConfiguration(_fileHandle, track.trackId,
                                               magicCookie.bytes,
                                               (uint32_t)magicCookie.length);
                }
                else if (track.conversionSettings.format == kAudioFormatAC3) {
                    const uint64_t *ac3Info = (const uint64_t *)magicCookie.bytes;

                    MP4SetTrackIntegerProperty(_fileHandle, track.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.fscod",           ac3Info[0]);
                    MP4SetTrackIntegerProperty(_fileHandle, track.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.bsid",            ac3Info[1]);
                    MP4SetTrackIntegerProperty(_fileHandle, track.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.bsmod",           ac3Info[2]);
                    MP4SetTrackIntegerProperty(_fileHandle, track.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.acmod",           ac3Info[3]);
                    MP4SetTrackIntegerProperty(_fileHandle, track.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.lfeon",           ac3Info[4]);
                    MP4SetTrackIntegerProperty(_fileHandle, track.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.bit_rate_code",   ac3Info[5]);
                }
            }
            else {
                [_logger writeToLog:@"MagicCookie not found"];
            }
        }
    }

    // Stop the importers and clean ups
    if (!_cancelled) {
        for (MP42FileImporter *importerHelper in trackImportersArray) {
            for (MP42Track *track in importerHelper.outputsTracks)
                [importerHelper cleanUp:track fileHandle:_fileHandle];
        }
    }
}

- (void)cancel
{
    bool expected = false;
    if (atomic_compare_exchange_strong(&_readingCancelled, &expected, true)) {
        dispatch_semaphore_wait(_setupDone, DISPATCH_TIME_FOREVER);
        for (MP42FileImporter *importerHelper in self.fileImporters) {
            [importerHelper cancelReading];
        }
    }
}

- (NSArray<MP42FileImporter *> *)fileImporters
{
    NSMutableArray<MP42FileImporter *> *trackImportersArray = [NSMutableArray array];

    for (MP42Track *track in _activeTracks) {
        if (![trackImportersArray containsObject:track.importer]) {
            [trackImportersArray addObject:track.importer];
        }
    }
    return [trackImportersArray copy];
}

@end
