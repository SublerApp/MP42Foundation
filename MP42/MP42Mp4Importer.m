//
//  MP42Mp4Importer.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2022 Damiano Galassi All rights reserved.
//

#import "MP42Mp4Importer.h"
#import "MP42FileImporter+Private.h"
#import "MP42File.h"

#import "MP42SampleBuffer.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Private.h"

typedef struct MP4DemuxHelper {
    MP4TrackId sourceID;

    MP4SampleId     currentSampleId;
    uint64_t        totalSampleNumber;
    MP4Timestamp    currentTime;
    uint32_t        timeScale;

    uint32_t        done;
} MP4DemuxHelper;

@implementation MP42Mp4Importer {
@private
    MP42FileHandle   _fileHandle;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"mp4", @"m4v", @"m4a", @"m4r"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError * __autoreleasing *)outError
{
    if ((self = [super initWithURL:fileURL])) {
        MP42File *sourceFile = [[MP42File alloc] initWithURL:self.fileURL error:outError];

        if (!sourceFile) {
            return nil;
        }

        [self addTracks:sourceFile.tracks];
        [self.metadata mergeMetadata:sourceFile.metadata];
    }

    return self;
}

- (NSData *)magicCookieForTrack:(MP42Track *)track
{
    if (!_fileHandle) {
        _fileHandle = MP4Read(self.fileURL.fileSystemRepresentation);
    }

    NSData *magicCookie = nil;
    MP4TrackId srcTrackId = track.sourceId;

    const char *trackType = MP4GetTrackType(_fileHandle, srcTrackId);
    const char *media_data_name = MP4GetTrackMediaDataName(_fileHandle, srcTrackId, 0);

    if (!trackType) {
        return nil;
    }

    if (MP4_IS_AUDIO_TRACK_TYPE(trackType)){

        if (!strcmp(media_data_name, "ac-3")) {

            uint64_t fscod, bsid, bsmod, acmod, lfeon, bit_rate_code;
            MP4GetTrackIntegerProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ac-3.dac3.fscod", &fscod);
            MP4GetTrackIntegerProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ac-3.dac3.bsid", &bsid);
            MP4GetTrackIntegerProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ac-3.dac3.bsmod", &bsmod);
            MP4GetTrackIntegerProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ac-3.dac3.acmod", &acmod);
            MP4GetTrackIntegerProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ac-3.dac3.lfeon", &lfeon);
            MP4GetTrackIntegerProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ac-3.dac3.bit_rate_code", &bit_rate_code);

            NSMutableData *ac3Info = [[NSMutableData alloc] init];
            [ac3Info appendBytes:&fscod length:sizeof(uint64_t)];
            [ac3Info appendBytes:&bsid length:sizeof(uint64_t)];
            [ac3Info appendBytes:&bsmod length:sizeof(uint64_t)];
            [ac3Info appendBytes:&acmod length:sizeof(uint64_t)];
            [ac3Info appendBytes:&lfeon length:sizeof(uint64_t)];
            [ac3Info appendBytes:&bit_rate_code length:sizeof(uint64_t)];

            return ac3Info;
        }
        else if (!strcmp(media_data_name, "ec-3")) {
            if (MP4HaveTrackAtom(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ec-3.dec3")) {
                uint8_t    *ppValue;
                uint32_t    pValueSize;
                MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.ec-3.dec3.content", &ppValue, &pValueSize);
                magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
                free(ppValue);
            }
        }
        else if (!strcmp(media_data_name, "alac")) {
            if (MP4HaveTrackAtom(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.alac.alac")) {
                uint8_t    *ppValue;
                uint32_t    pValueSize;
                MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.alac.alac.AppleLosslessMagicCookie", &ppValue, &pValueSize);
                magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
                free(ppValue);
            }
        }
        else if (!strcmp(media_data_name, "mp4a")) {
            uint8_t *ppConfig; uint32_t pConfigSize;
            MP4GetTrackESConfiguration(_fileHandle, srcTrackId, &ppConfig, &pConfigSize);
            magicCookie = [NSData dataWithBytes:ppConfig length:pConfigSize];
            free(ppConfig);
        }
        return magicCookie;
    }

    else if (!strcmp(trackType, MP4_SUBPIC_TRACK_TYPE)) {
        uint8_t *ppConfig; uint32_t pConfigSize;
        MP4GetTrackESConfiguration(_fileHandle, srcTrackId, &ppConfig, &pConfigSize);

        UInt32* paletteG = (UInt32 *) ppConfig;

        int ii;
        for ( ii = 0; ii < 16; ii++ )
            paletteG[ii] = yuv2rgb(EndianU32_BtoN(paletteG[ii]));

        magicCookie = [NSData dataWithBytes:paletteG length:pConfigSize];
        free(paletteG);

        return magicCookie;
    }

    else if (MP4_IS_VIDEO_TRACK_TYPE(trackType)) {

        if (!strcmp(media_data_name, "avc1")) {

            // Extract and rewrite some kind of avcC extradata from the mp4 file.
            NSMutableData *avcCData = [[NSMutableData alloc] init];

            uint8_t configurationVersion = 1;
            uint8_t AVCProfileIndication;
            uint8_t profile_compat;
            uint8_t AVCLevelIndication;
            uint32_t sampleLenFieldSizeMinusOne;
            uint64_t temp;

            if (MP4GetTrackH264ProfileLevel(_fileHandle, srcTrackId,
                                            &AVCProfileIndication,
                                            &AVCLevelIndication) == false) {
                return nil;
            }
            if (MP4GetTrackH264LengthSize(_fileHandle, srcTrackId,
                                          &sampleLenFieldSizeMinusOne) == false) {
                return nil;
            }
            sampleLenFieldSizeMinusOne--;
            if (MP4GetTrackIntegerProperty(_fileHandle, srcTrackId,
                                           "mdia.minf.stbl.stsd.*[0].avcC.profile_compatibility",
                                           &temp) == false) return nil;
            profile_compat = temp & 0xff;

            [avcCData appendBytes:&configurationVersion length:sizeof(uint8_t)];
            [avcCData appendBytes:&AVCProfileIndication length:sizeof(uint8_t)];
            [avcCData appendBytes:&profile_compat length:sizeof(uint8_t)];
            [avcCData appendBytes:&AVCLevelIndication length:sizeof(uint8_t)];
            [avcCData appendBytes:&sampleLenFieldSizeMinusOne length:sizeof(uint8_t)];

            uint8_t **seqheader, **pictheader;
            uint32_t *pictheadersize, *seqheadersize;
            uint32_t ix, iy;
            MP4GetTrackH264SeqPictHeaders(_fileHandle, srcTrackId,
                                          &seqheader, &seqheadersize,
                                          &pictheader, &pictheadersize);
            NSMutableData *seqData = [[NSMutableData alloc] init];
            for (ix = 0 , iy = 0; seqheadersize[ix] != 0; ix++) {
                uint16_t tempSeqSize = seqheadersize[ix] << 8;
                [seqData appendBytes:&tempSeqSize length:sizeof(uint16_t)];
                [seqData appendBytes:seqheader[ix] length:seqheadersize[ix]];
                iy++;
                free(seqheader[ix]);
            }
            [avcCData appendBytes:&iy length:sizeof(uint8_t)];
            [avcCData appendData:seqData];

            free(seqheader);
            free(seqheadersize);

            NSMutableData *pictData = [[NSMutableData alloc] init];
            for (ix = 0, iy = 0; pictheadersize[ix] != 0; ix++) {
                uint16_t tempPictSize = pictheadersize[ix] << 8;
                [pictData appendBytes:&tempPictSize length:sizeof(uint16_t)];
                [pictData appendBytes:pictheader[ix] length:pictheadersize[ix]];
                iy++;
                free(pictheader[ix]);
            }

            [avcCData appendBytes:&iy length:sizeof(uint8_t)];
            [avcCData appendData:pictData];

            free(pictheader);
            free(pictheadersize);
            
            magicCookie = [avcCData copy];

            return magicCookie;
        }
        else if (!strcmp(media_data_name, "hev1")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.hev1.hvcC.content", &ppValue, &pValueSize);
            magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
            free(ppValue);
            return magicCookie;
        }
        else if (!strcmp(media_data_name, "hvc1")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.hvc1.hvcC.content", &ppValue, &pValueSize);
            magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
            free(ppValue);
            return magicCookie;
        }
        else if (!strcmp(media_data_name, "dvhe")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.dvhe.hvcC.content", &ppValue, &pValueSize);
            magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
            free(ppValue);
            return magicCookie;
        }
        else if (!strcmp(media_data_name, "dvh1")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.dvh1.hvcC.content", &ppValue, &pValueSize);
            magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
            free(ppValue);
            return magicCookie;
        }
        else if (!strcmp(media_data_name, "vvc1")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.vvc1.vvcC.content", &ppValue, &pValueSize);
            magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
            free(ppValue);
            return magicCookie;
        }
        else if (!strcmp(media_data_name, "vvic")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.vvic.vvcC.content", &ppValue, &pValueSize);
            magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
            free(ppValue);
            return magicCookie;
        }
        else if (!strcmp(media_data_name, "av01")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.av01.av1C.av1Config", &ppValue, &pValueSize);
            magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
            free(ppValue);
            return magicCookie;
        }
        else if (!strcmp(media_data_name, "mp4v")) {
            uint8_t *ppConfig; uint32_t pConfigSize;
            MP4GetTrackESConfiguration(_fileHandle, srcTrackId, &ppConfig, &pConfigSize);
            magicCookie = [NSData dataWithBytes:ppConfig length:pConfigSize];
            free(ppConfig);

            return magicCookie;
        }
    }

    else if ((!strcasecmp(trackType, MP4_TEXT_TRACK_TYPE))) {

        if (!strcmp(media_data_name, "wvtt")) {
            if (MP4HaveTrackAtom(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.wvtt.vttC")) {
                uint8_t    *ppValue;
                uint32_t    pValueSize;
                MP4GetTrackBytesProperty(_fileHandle, srcTrackId, "mdia.minf.stbl.stsd.wvtt.vttC.config", &ppValue, &pValueSize);
                magicCookie = [NSData dataWithBytes:ppValue length:pValueSize];
                free(ppValue);
                return magicCookie;
            }
        }
    }

    return nil;
}

- (AudioStreamBasicDescription)audioDescriptionForTrack:(MP42AudioTrack *)track
{
    AudioStreamBasicDescription result;
    bzero(&result, sizeof(AudioStreamBasicDescription));

    MP42TrackId trackID = track.sourceId;

    if (MP4HaveTrackAtom(_fileHandle, trackID, "mdia.minf.stbl.stsd.twos")) {
        uint64_t channels_count = 0;
        uint64_t sample_rate = 0;
        uint64_t bit_depth = 0;

        MP4GetTrackIntegerProperty(_fileHandle, trackID, "mdia.minf.stbl.stsd.twos.channels", &channels_count);
        MP4GetTrackIntegerProperty(_fileHandle, trackID, "mdia.minf.stbl.stsd.twos.timeScale", &sample_rate);
        MP4GetTrackIntegerProperty(_fileHandle, trackID, "mdia.minf.stbl.stsd.twos.sampleSize", &bit_depth);

        result.mSampleRate = (sample_rate >> 16) + (sample_rate & 0xffff) / 65536.0;
        result.mFormatID = kAudioFormatLinearPCM;
        result.mFormatFlags +=  kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
        result.mBitsPerChannel = (UInt32)bit_depth;
        result.mChannelsPerFrame = (UInt32)channels_count;
    }

    return result;
}

- (BOOL)audioTrackUsesExplicitEncoderDelay:(MP42Track *)track
{
    return MP4HaveTrackAtom(_fileHandle, track.sourceId, "mdia.minf.stbl.sgpd");
}

- (void)demux
{
    @autoreleasepool {

        if (!_fileHandle) {
            return;
        }

        NSArray<MP42Track *> *inputTracks = self.inputTracks;
        NSUInteger tracksNumber = inputTracks.count;
        NSUInteger tracksDone = 0;

        MP4DemuxHelper * helpers[tracksNumber];

        for (NSUInteger index = 0; index < tracksNumber; index += 1) {
            MP42Track *track = inputTracks[index];
            MP4DemuxHelper *demuxHelper = calloc(1, sizeof(MP4DemuxHelper));
            demuxHelper->sourceID = track.sourceId;
            demuxHelper->totalSampleNumber = MP4GetTrackNumberOfSamples(_fileHandle, track.sourceId);
            demuxHelper->timeScale = MP4GetTrackTimeScale(_fileHandle, track.sourceId);
            demuxHelper->done = 0;

            helpers[index] = demuxHelper;
        }

        MP4Timestamp currentTime = 1;
        MP4Duration totalDuration = MP4GetDuration(_fileHandle);
        MP4Duration timescale = MP4GetTimeScale(_fileHandle);

        while (tracksDone != tracksNumber) {
            if (self.isCancelled) {
                break;
            }

            for (NSUInteger index = 0; index < tracksNumber; index += 1) {
                MP4DemuxHelper *demuxHelper = helpers[index];

                if (self.isCancelled) {
                    break;
                }

                while (demuxHelper->currentTime < demuxHelper->timeScale * currentTime && !demuxHelper->done) {
                    uint8_t *pBytes = NULL;
                    uint32_t numBytes = 0;
                    MP4Duration duration;
                    MP4Duration renderingOffset;
                    MP4Timestamp pStartTime;
                    unsigned char isSyncSample;
                    unsigned char hasDependencyFlags;
                    uint32_t dependencyFlags;

                    demuxHelper->currentSampleId = demuxHelper->currentSampleId + 1;
                    if (demuxHelper->currentSampleId > demuxHelper->totalSampleNumber) {
                        demuxHelper->done++;
                        tracksDone++;
                        break;
                    }

                    if (!MP4ReadSampleSampleDependency(_fileHandle,
                                       demuxHelper->sourceID,
                                       demuxHelper->currentSampleId,
                                       &pBytes, &numBytes,
                                       &pStartTime, &duration, &renderingOffset,
                                       &isSyncSample, &hasDependencyFlags, &dependencyFlags)) {
                        demuxHelper->done++;
                        tracksDone++;
                        break;
                    }

                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->data = pBytes;
                    sample->size = numBytes;
                    sample->timescale = demuxHelper->timeScale;
                    sample->duration = duration;
                    sample->offset = renderingOffset;
                    sample->decodeTimestamp = pStartTime;
                    sample->flags |= isSyncSample ? MP42SampleBufferFlagIsSync : 0;
                    sample->trackId = demuxHelper->sourceID;
                    if (hasDependencyFlags) {
                        sample->dependecyFlags = dependencyFlags;
                    }
                    
                    [self enqueue:sample];

                    demuxHelper->currentTime = pStartTime;
                }
            }

            self.progress = ((CGFloat)currentTime * timescale / totalDuration) * 100;
            currentTime += 3;
        }

        [self setDone];

        for (NSUInteger index = 0; index < tracksNumber; index += 1) {
            free(helpers[index]);
        }
    }
}

- (void)cleanUp:(MP42Track *)track fileHandle:(MP4FileHandle)dstFileHandle
{
    MP4TrackId srcTrackId = track.sourceId;
    MP4TrackId dstTrackId = track.trackId;
    
    MP4Duration trackDuration = 0;
    uint32_t i = 1, trackEditCount = MP4GetTrackNumberOfEdits(_fileHandle, srcTrackId);
    while (i <= trackEditCount) {
        MP4Timestamp editMediaStart = MP4GetTrackEditMediaStart(_fileHandle, srcTrackId, i);
        MP4Duration editDuration = MP4ConvertFromMovieDuration(_fileHandle,
                                                               MP4GetTrackEditDuration(_fileHandle, srcTrackId, i),
                                                               MP4GetTimeScale(dstFileHandle));
        trackDuration += editDuration;
        int8_t editDwell = MP4GetTrackEditDwell(_fileHandle, srcTrackId, i);
        
        MP4AddTrackEdit(dstFileHandle, dstTrackId, i, editMediaStart, editDuration, editDwell);
        i++;
    }
    if (trackEditCount) {
        MP4SetTrackIntegerProperty(dstFileHandle, dstTrackId, "tkhd.duration", trackDuration);
    }
    else if (MP4GetSampleRenderingOffset(dstFileHandle, dstTrackId, 1)) {
        MP4Duration firstFrameOffset = MP4GetSampleRenderingOffset(dstFileHandle, dstTrackId, 1);
        
        MP4Duration editDuration = MP4ConvertFromTrackDuration(_fileHandle,
                                                               srcTrackId,
                                                               MP4GetTrackDuration(_fileHandle, srcTrackId),
                                                               MP4GetTimeScale(dstFileHandle));
        
        MP4AddTrackEdit(dstFileHandle, dstTrackId, MP4_INVALID_EDIT_ID, firstFrameOffset,
                        editDuration, 0);
    }
}

- (NSString *)description
{
    return @"MP4 demuxer";
}

- (void)dealloc
{
    if (_fileHandle) {
        MP4Close(_fileHandle, 0);
    }
}

@end
