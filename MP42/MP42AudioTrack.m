//
//  MP42SubtitleTrack.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import "MP42AudioTrack.h"
#import "MP42Track+Private.h"

#import "MP42PrivateUtilities.h"
#import "MP42FormatUtilites.h"
#import "MP42MediaFormat.h"

#define FFmpegMaximumSupportedChannels  6

@implementation MP42AudioTrack {
@private
    float _volume;
    UInt32 _channels;
    UInt32 _channelLayoutTag;

    MP42TrackId  _fallbackTrackId;
    MP42TrackId  _followsTrackId;

    MP42Track  *_fallbackTrack;
    MP42Track  *_followsTrack;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP4FileHandle)fileHandle
{
    self = [super initWithSourceURL:URL trackID:trackID fileHandle:fileHandle];

    if (self) {
        MP4GetTrackFloatProperty(fileHandle, self.trackId, "tkhd.volume", &_volume);
        const char *dataName = MP4GetTrackMediaDataName(fileHandle, self.trackId);

        if (dataName && !strcmp(dataName, "mp4a")) {
            u_int8_t audioType = MP4GetTrackEsdsObjectTypeId(fileHandle, self.trackId);

            if (audioType != MP4_INVALID_AUDIO_TYPE) {
                if (MP4_IS_AAC_AUDIO_TYPE(audioType)) {
                    u_int8_t* pAacConfig = NULL;
                    u_int32_t aacConfigLength;

                    if (MP4GetTrackESConfiguration(fileHandle,
                                                   self.trackId,
                                                   &pAacConfig,
                                                   &aacConfigLength) == true)
                        if (pAacConfig != NULL || aacConfigLength >= 2) {
                            MPEG4AudioConfig c = {0};
                            analyze_ESDS(&c, pAacConfig, aacConfigLength);
                            _channels = c.channels;
                            free(pAacConfig);
                        }

                    if (!MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.sgpd")) {
                        BOOL addDelay = YES;
                        uint32_t edits = MP4GetTrackNumberOfEdits(fileHandle, self.trackId);
                        if (edits == 1) {
                            MP4Timestamp startTime = MP4GetTrackEditMediaStart(fileHandle, self.trackId, 1);
                            if (startTime != 0) {
                                addDelay = NO;
                            }
                        }
                        if (addDelay) {
                            // Guess a audio encoder delay
                            self.startOffset = -2112.f / self.timescale * 1000;
                        }
                    }
                }
                else if ((audioType == MP4_PCM16_LITTLE_ENDIAN_AUDIO_TYPE) ||
                         (audioType == MP4_PCM16_BIG_ENDIAN_AUDIO_TYPE)) {

                    u_int32_t samplesPerFrame =
                    MP4GetSampleSize(fileHandle, self.trackId, 1) / 2;

                    MP4Duration frameDuration =
                    MP4GetSampleDuration(fileHandle, self.trackId, 1);

                    if (frameDuration != 0) {
                        // assumes track time scale == sampling rate
                        _channels = samplesPerFrame / frameDuration;
                    }
                }
            }

            if (audioType == 0xA9) {
                uint64_t channels_count = 0;
                MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.mp4a.channels", &channels_count);
                _channels = channels_count;
            }
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.ac-3.dac3")) {
            uint64_t acmod, lfeon;

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.acmod", &acmod);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.ac-3.dac3.lfeon", &lfeon);

            readAC3Config(acmod, lfeon, &_channels, &_channelLayoutTag);
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.ec-3.dec3")) {
            uint8_t    *ppValue;
            uint32_t    pValueSize;
            MP4GetTrackBytesProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.ec-3.dec3.content", &ppValue, &pValueSize);
            readEAC3Config(ppValue, pValueSize, &_channels, &_channelLayoutTag);
            free(ppValue);
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.alac")) {
            uint64_t channels_count = 0;
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.alac.channels", &channels_count);
            _channels = channels_count;
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.twos")) {
            uint64_t channels_count = 0;
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.twos.channels", &channels_count);
            _channels = channels_count;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "tref.fall")) {
            uint64_t fallbackId = 0;
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "tref.fall.entries.trackId", &fallbackId);
            _fallbackTrackId = (MP4TrackId) fallbackId;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "tref.folw")) {
            uint64_t followsId = 0;
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "tref.folw.entries.trackId", &followsId);
            _followsTrackId = (MP4TrackId) followsId;
        }

    }

    return self;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.mediaType = kMP42MediaType_Audio;
        _volume = 1;
    }
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    MP42AudioTrack *copy = [super copyWithZone:zone];

    if (copy) {
        copy->_volume = _volume;
        copy->_channels = _channels;
        copy->_channelLayoutTag = _channelLayoutTag;

        copy->_fallbackTrackId = _fallbackTrackId;
        copy->_followsTrackId = _followsTrackId;
    }
    
    return copy;
}

- (BOOL)writeToFile:(MP4FileHandle)fileHandle error:(NSError **)outError
{
    if (!fileHandle) {
        return NO;
    }

    if (self.trackId) {
        [super writeToFile:fileHandle error:outError];
    }

    if (self.updatedProperty[@"volume"] || !self.muxed) {
        MP4SetTrackFloatProperty(fileHandle, self.trackId, "tkhd.volume", _volume);
    }

    if (self.updatedProperty[@"fallback"] || !self.muxed) {

        if (_fallbackTrack) {
            _fallbackTrackId = _fallbackTrack.trackId;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "tref.fall") && (_fallbackTrackId == 0)) {
            MP4RemoveAllTrackReferences(fileHandle, "tref.fall", self.trackId);
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "tref.fall") && (_fallbackTrackId)) {
            MP4SetTrackIntegerProperty(fileHandle, self.trackId, "tref.fall.entries.trackId", _fallbackTrackId);
        }
        else if (_fallbackTrackId) {
            MP4AddTrackReference(fileHandle, "tref.fall", _fallbackTrackId, self.trackId);
        }
    }
    
    if (self.updatedProperty[@"follows"] || !self.muxed) {

        if (_followsTrack) {
            _followsTrackId = _followsTrack.trackId;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "tref.folw") && (_followsTrackId == 0)) {
            MP4RemoveAllTrackReferences(fileHandle, "tref.folw", self.trackId);
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "tref.folw") && (_followsTrackId)) {
            MP4SetTrackIntegerProperty(fileHandle, self.trackId, "tref.folw.entries.trackId", _followsTrackId);
        }
        else if (_followsTrackId) {
            MP4AddTrackReference(fileHandle, "tref.folw", _followsTrackId, self.trackId);
        }
    }

    return (self.trackId > 0);
}

- (void)setConversionSettings:(MP42AudioConversionSettings *)conversionSettings
{
    [super setConversionSettings:conversionSettings];
    
    if (conversionSettings == nil) return;
    
    if ([self.name rangeOfString:@"surround" options:NSCaseInsensitiveSearch].location == NSNotFound) return;
    
    if ([conversionSettings.mixDown isEqualToString:SBNoneMixdown] && self.channels > 3) {
        self.name = (self.channels > FFmpegMaximumSupportedChannels) ? [NSString stringWithFormat:@"Surround %d.1", FFmpegMaximumSupportedChannels - 1] : nameForChannelLayoutTag(self.channelLayoutTag);
    }
    else {
        self.name = (self.channels == 1 || [conversionSettings.mixDown isEqualToString:SBMonoMixdown]) ? @"Mono" : @"Stereo";
    }
}

- (void)setVolume:(float)newVolume
{
    _volume = newVolume;
    self.edited = YES;
    self.updatedProperty[@"volume"] = @YES;
}

- (float)volume
{
    return _volume;
}

- (void)setFallbackTrack:(MP42Track *)newFallbackTrack
{
    _fallbackTrack = newFallbackTrack;
    _fallbackTrackId = 0;
    self.edited = YES;
    self.updatedProperty[@"fallback"] = @YES;
}

- (MP42Track *)fallbackTrack
{
    return _fallbackTrack;
}

- (void)setFollowsTrack:(MP42Track *)newFollowsTrack
{
    _followsTrack = newFollowsTrack;
    _followsTrackId = 0;
    self.edited = YES;
    self.updatedProperty[@"follows"] = @YES;
}

- (MP42Track *)followsTrack
{
    return _followsTrack;
}

- (NSString *)formatSummary
{
    if (self.conversionSettings && [self.conversionSettings isKindOfClass:[MP42AudioConversionSettings class]]) {
        MP42AudioConversionSettings *settings = (MP42AudioConversionSettings *)self.conversionSettings;
        unsigned int channels = _channels;
        if ([settings.mixDown isEqualToString:SBMonoMixdown] || self.channels == 1) {
            channels = 1;
        }
        else if ([settings.mixDown isEqualToString:SBNoneMixdown]) {
            channels = MIN(channels, FFmpegMaximumSupportedChannels);
        }
        else {
            channels = 2;
        }
        return [NSString stringWithFormat:@"%@, %u ch", localizedDisplayName(self.mediaType, self.conversionSettings.format), channels];
    }
    else {
        return [NSString stringWithFormat:@"%@, %u ch", localizedDisplayName(self.mediaType, self.format), (unsigned int)_channels];
    }
}

- (NSString *)description {
    return [[super description] stringByAppendingFormat:@", %u ch", (unsigned int)_channels];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    [coder encodeInt:1 forKey:@"MP42AudioTrackVersion"];

    [coder encodeFloat:_volume forKey:@"volume"];

    [coder encodeInt64:_channels forKey:@"channels"];
    [coder encodeInt64:_channelLayoutTag forKey:@"channelLayoutTag"];

    [coder encodeInt64:_fallbackTrackId forKey:@"fallbackTrackId"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    _volume = [decoder decodeFloatForKey:@"volume"];

    _channels = [decoder decodeInt64ForKey:@"channels"];
    _channelLayoutTag = [decoder decodeInt64ForKey:@"channelLayoutTag"];

    _fallbackTrackId = [decoder decodeInt64ForKey:@"fallbackTrackId"];

    return self;
}

@end
