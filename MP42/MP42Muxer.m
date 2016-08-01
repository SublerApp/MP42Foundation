//
//  MP42Muxer.m
//  Subler
//
//  Created by Damiano Galassi on 30/06/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import "MP42Muxer.h"

#import "MP42File.h"
#import "MP42FileImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42Sample.h"
#import "MP42AudioConverter.h"
#import "MP42BitmapSubConverter.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Muxer.h"

@implementation MP42Muxer
{
@private
    MP4FileHandle    _fileHandle;

    id <MP42MuxerDelegate>  _delegate;
    id <MP42Logging>        _logger;

    NSMutableArray<MP42Track *> *_workingTracks;
    int32_t         _cancelled;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _workingTracks = [[NSMutableArray alloc] init];
    }
    return self;
}

- (instancetype)initWithFileHandle:(MP4FileHandle)fileHandle delegate:(id <MP42MuxerDelegate>)del logger:(id <MP42Logging>)logger
{
    if ((self = [self init])) {
        NSParameterAssert(fileHandle);
        _fileHandle = fileHandle;
        _delegate = del;
        _logger = [logger retain];
    }

    return self;
}

- (void)dealloc
{
    [_logger release];
    [_workingTracks release];
    [super dealloc];
}

- (BOOL)canAddTrack:(MP42Track *)track
{
    if (isTrackMuxable(track.format)) {
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
    if (![track isMemberOfClass:[MP42ChapterTrack class]])
        [_workingTracks addObject:track];
}

- (BOOL)setup:(NSError **)outError
{
    NSMutableArray<MP42Track *> *unsupportedTracks = [[NSMutableArray alloc] init];;

    for (MP42Track *track in _workingTracks) {

        MP4TrackId dstTrackId = 0;
        NSData *magicCookie = nil;
        NSInteger timeScale = 0;
        muxer_helper *helper = track.muxer_helper;

        if (helper) {
            magicCookie = [helper->importer magicCookieForTrack:track];
            timeScale = [helper->importer timescaleForTrack:track];
        }
        else {
            [unsupportedTracks addObject:track];
            continue;
        }

        // Setup the converters
        if ([track isMemberOfClass:[MP42AudioTrack class]] && track.needConversion) {
            MP42AudioConverter *audioConverter = [[MP42AudioConverter alloc] initWithTrack:(MP42AudioTrack *)track
                                                                        andMixdownType:[(MP42AudioTrack *)track mixdownType]
                                                                                 error:outError];

            if (audioConverter == nil) {
                if (outError && *outError) {
                    [_logger writeErrorToLog:*outError];
                }
                [unsupportedTracks addObject:track];
                continue;
            }

            helper->converter = audioConverter;
        }
        if ([track isMemberOfClass:[MP42SubtitleTrack class]] && ([track.sourceFormat isEqualToString:MP42SubtitleFormatVobSub] || [track.sourceFormat isEqualToString:MP42SubtitleFormatPGS]) && track.needConversion) {
            MP42BitmapSubConverter *subConverter = [[MP42BitmapSubConverter alloc] initWithTrack:(MP42SubtitleTrack *)track
                                                                                       error:outError];

            if (subConverter == nil) {
                if (outError && *outError) {
                    [_logger writeErrorToLog:*outError];
                }
                [unsupportedTracks addObject:track];
                continue;
            }

            helper->converter = subConverter;
        } else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && track.needConversion) {
            track.format = MP42SubtitleFormatTx3g;
        }

        // H.264 video track
        if ([track isMemberOfClass:[MP42VideoTrack class]] && [track.format isEqualToString:MP42VideoFormatH264]) {

            if (magicCookie.length < sizeof(uint8_t) * 6) {
                continue;
            }

            NSSize size = [helper->importer sizeForTrack:track];

            uint8_t *avcCAtom = (uint8_t *)[magicCookie bytes];
            dstTrackId = MP4AddH264VideoTrack(_fileHandle, timeScale,
                                              MP4_INVALID_DURATION,
                                              size.width, size.height,
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

            [helper->importer setActiveTrack:track];
        }

        // H.265 video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] && [track.format isEqualToString:MP42VideoFormatH265]) {

            if (magicCookie.length < sizeof(uint8_t) * 6) {
                continue;
            }

            //NSSize size = [helper->importer sizeForTrack:track];
            //uint8_t *hvCCAtom = (uint8_t *)magicCookie.bytes;

            NSAssert(NO, @"H.265 muxing not implemented yet");

            [helper->importer setActiveTrack:track];
        }

        // MPEG-4 Visual video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] && [track.format isEqualToString:MP42VideoFormatMPEG4Visual]) {
            MP4SetVideoProfileLevel(_fileHandle, MPEG4_SP_L3);
            // Add video track
            dstTrackId = MP4AddVideoTrack(_fileHandle, timeScale,
                                          MP4_INVALID_DURATION,
                                          [(MP42VideoTrack*)track width], [(MP42VideoTrack*)track height],
                                          MP4_MPEG4_VIDEO_TYPE);

            if (magicCookie.length) {
                MP4SetTrackESConfiguration(_fileHandle, dstTrackId,
                                           magicCookie.bytes,
                                           magicCookie.length);
            }

            [helper->importer setActiveTrack:track];
        }

        // Photo-JPEG video track
        else if ([track isMemberOfClass:[MP42VideoTrack class]] && [track.format isEqualToString:MP42VideoFormatJPEG]) {
            // Add video track
            dstTrackId = MP4AddJpegVideoTrack(_fileHandle, timeScale,
                                  MP4_INVALID_DURATION, [(MP42VideoTrack*)track width], [(MP42VideoTrack*)track height]);

            [helper->importer setActiveTrack:track];
        }

        // AAC audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] &&
                 ([track.format isEqualToString:MP42AudioFormatAAC] || [track.format isEqualToString:MP42AudioFormatHEAAC])) {
            dstTrackId = MP4AddAudioTrack(_fileHandle,
                                          timeScale,
                                          1024, MP4_MPEG4_AUDIO_TYPE);

            if (!track.needConversion && [magicCookie length]) {
                MP4SetTrackESConfiguration(_fileHandle, dstTrackId,
                                           [magicCookie bytes],
                                           [magicCookie length]);
            }
            
            [helper->importer setActiveTrack:track];
        }

        // AC-3 audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && [track.format isEqualToString:MP42AudioFormatAC3]) {
            if ([magicCookie length] < sizeof(uint64_t) * 6)
                continue;

            const uint64_t *ac3Info = (const uint64_t *)[magicCookie bytes];

            dstTrackId = MP4AddAC3AudioTrack(_fileHandle,
                                             timeScale,
                                             ac3Info[0],
                                             ac3Info[1],
                                             ac3Info[2],
                                             ac3Info[3],
                                             ac3Info[4],
                                             ac3Info[5]);

            [helper->importer setActiveTrack:track];
        }

        // EAC-3 audio tack
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && [track.format isEqualToString:MP42AudioFormatEAC3]) {
            dstTrackId = MP4AddEAC3AudioTrack(_fileHandle, timeScale, magicCookie.bytes, magicCookie.length);

            [helper->importer setActiveTrack:track];
        }

        // ALAC audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && [track.format isEqualToString:MP42AudioFormatALAC]) {
            dstTrackId = MP4AddALACAudioTrack(_fileHandle,
                                          timeScale);
            if (magicCookie.length) {
                MP4SetTrackBytesProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.alac.alac.AppleLosslessMagicCookie", magicCookie.bytes, magicCookie.length);
            }

            [helper->importer setActiveTrack:track];
        }

        // DTS audio track
        else if ([track isMemberOfClass:[MP42AudioTrack class]] && [track.format isEqualToString:MP42AudioFormatDTS]) {
            dstTrackId = MP4AddAudioTrack(_fileHandle,
                                          timeScale,
                                          512, 0xA9);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.*.channels", [(MP42AudioTrack*)track channels]);
            [helper->importer setActiveTrack:track];
        }

        // 3GPP text track
        else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && [track.format isEqualToString:MP42SubtitleFormatTx3g]) {
            NSSize subSize = NSMakeSize(0, 0);
            NSSize videoSize = NSMakeSize(0, 0);

            NSInteger vPlacement = [(MP42SubtitleTrack*)track verticalPlacement];

            for (id workingTrack in _workingTracks) {
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
                if ([(MP42SubtitleTrack*)track trackHeight])
                    subSize.height = [(MP42SubtitleTrack*)track trackHeight];
                else
                    subSize.height = 0.15 * videoSize.height;
            }
            else {
                subSize.height = videoSize.height;
            }

            const uint8_t textColor[4] = { 255,255,255,255 };
            dstTrackId = MP4AddSubtitleTrack(_fileHandle, timeScale, videoSize.width, subSize.height);

            MP4SetTrackDurationPerChunk(_fileHandle, dstTrackId, timeScale / 8);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "tkhd.alternate_group", 2);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "tkhd.layer", -1);

            int32_t displayFlags = 0;
            if (vPlacement)
                displayFlags = 0x20000000;
            if ([(MP42SubtitleTrack *)track someSamplesAreForced])
                displayFlags += 0x40000000;
            if ([(MP42SubtitleTrack *)track allSamplesAreForced])
                displayFlags += 0xC0000000;

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.displayFlags", displayFlags);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.horizontalJustification", 1);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.verticalJustification", -1);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorRed", 0);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorGreen", 0);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorBlue", 0);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.bgColorAlpha", 0);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.defTextBoxBottom", subSize.height);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.defTextBoxRight", videoSize.width);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontSize", videoSize.height * 0.05);

            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorRed", textColor[0]);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorGreen", textColor[1]);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorBlue", textColor[2]);
            MP4SetTrackIntegerProperty(_fileHandle, dstTrackId, "mdia.minf.stbl.stsd.tx3g.fontColorAlpha", textColor[3]);

            /* translate the track */
            if (!vPlacement) {
                uint8_t* val;
                uint8_t nval[36];
                uint32_t *ptr32 = (uint32_t*) nval;
                uint32_t size;

                MP4GetTrackBytesProperty(_fileHandle, dstTrackId, "tkhd.matrix", &val, &size);
                memcpy(nval, val, size);
                ptr32[7] = CFSwapInt32HostToBig( (videoSize.height * 0.85) * 0x10000);

                MP4SetTrackBytesProperty(_fileHandle, dstTrackId, "tkhd.matrix", nval, size);
                free(val);
            }

            [(MP42SubtitleTrack*)track setTrackWidth:videoSize.width];
            [(MP42SubtitleTrack*)track setTrackHeight:subSize.height];

            [helper->importer setActiveTrack:track];
        }

        // VobSub bitmap track
        else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && [track.format isEqualToString:MP42SubtitleFormatVobSub]) {
            if (magicCookie.length < sizeof(uint32_t) * 16)
                continue;

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

            [helper->importer setActiveTrack:track];
        }

        // WebVTT
        else if ([track isMemberOfClass:[MP42SubtitleTrack class]] && [track.format isEqualToString:MP42SubtitleFormatWebVTT]) {
            NSSize videoSize = [helper->importer sizeForTrack:track];

            for (id workingTrack in _workingTracks)
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

            [helper->importer setActiveTrack:track];
        }

        // Closed Caption text track
        else if ([track isMemberOfClass:[MP42ClosedCaptionTrack class]]) {
            NSSize videoSize = [helper->importer sizeForTrack:track];

            for (id workingTrack in _workingTracks)
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

            dstTrackId = MP4AddCCTrack(_fileHandle, timeScale, videoSize.width, videoSize.height);

            [helper->importer setActiveTrack:track];
        } else {
            [unsupportedTracks addObject:track];
            continue;
        }

        if (dstTrackId) {
            MP4SetTrackDurationPerChunk(_fileHandle, dstTrackId, timeScale / 8);
            track.trackId = dstTrackId;
        }
    }

    [_workingTracks removeObjectsInArray:unsupportedTracks];
    [unsupportedTracks release];

    return YES;
}

- (void)work
{
    if (!_workingTracks.count) {
        return;
    }

    NSArray<MP42FileImporter *> *trackImportersArray = self.fileImporters;
    NSUInteger done = 0, update = 0;
    CGFloat progress = 0;

    for (MP42FileImporter *importerHelper in trackImportersArray) {
        [importerHelper startReading];
    }

    NSUInteger tracksImportersCount = trackImportersArray.count;
    NSUInteger tracksCount = _workingTracks.count;

    for (;;) {
        @autoreleasepool {

            usleep(1000);

            // Iterate the tracks array and mux the samples
            for (MP42Track *track in _workingTracks) {
                MP42SampleBuffer *sampleBuffer = nil;
                MP42TrackId trackId = track.trackId;

                for (int i = 0; i < 100 && (sampleBuffer = [track copyNextSample]) != nil; i++) {

                    // Check if the track helper is done.
                    if (sampleBuffer->flags & MP42SampleBufferFlagEndOfFile) {
                        track.muxer_helper->done = 1;
                    }

                    else if (!MP4WriteSample(_fileHandle, trackId,
                                             sampleBuffer->data, sampleBuffer->size,
                                             sampleBuffer->duration, sampleBuffer->offset,
                                             sampleBuffer->flags & MP42SampleBufferFlagIsSync)) {
                        _cancelled = YES;
                    }

                    [sampleBuffer release];
                }
                done += (track.muxer_helper->done ? 1 : 0);
            }

            if (_cancelled) {
                break;
            }

            // If all tracks are done, exit the loop
            if (done == tracksCount) {
                break;
            } else {
                done = 0;
            }

            // Update progress
            if (!(update % 200)) {
                progress = 0;
                for (MP42FileImporter *importerHelper in trackImportersArray) {
                    progress += [importerHelper progress];
                }

                progress /= tracksImportersCount;

                [_delegate progressStatus:progress];
            }
            update++;
        }
    }

    // Write the converted audio track magic cookie
    for (MP42Track *track in _workingTracks) {
        if(track.muxer_helper->converter && track.needConversion && [track isMemberOfClass:[MP42AudioTrack class]]) {
            NSData *magicCookie = [track.muxer_helper->converter magicCookie];
            MP4SetTrackESConfiguration(_fileHandle, track.trackId,
                                       magicCookie.bytes,
                                       magicCookie.length);
        }
    }

    // Stop the importers and clean ups
    for (MP42FileImporter *importerHelper in trackImportersArray) {
        if (!_cancelled) {
            [importerHelper cleanUp:_fileHandle];
        }
    }
}

- (void)cancel
{
    for (MP42FileImporter *importerHelper in self.fileImporters) {
        [importerHelper cancelReading];
    }
}

- (NSArray<MP42FileImporter *> *)fileImporters
{
    NSMutableArray<MP42FileImporter *> *trackImportersArray = [NSMutableArray array];

    for (MP42Track *track in _workingTracks) {
        if (![trackImportersArray containsObject:track.muxer_helper->importer]) {
            [trackImportersArray addObject:track.muxer_helper->importer];
        }
    }
    return [[trackImportersArray copy] autorelease];
}

@end
