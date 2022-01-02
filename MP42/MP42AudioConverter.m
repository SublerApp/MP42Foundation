//
//  MP42AudioConverter.m
//  Subler
//
//  Created by Damiano Galassi on 16/09/10.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42AudioConverter.h"
#import "MP42AudioTrack.h"
#import "MP42MediaFormat.h"

#import "MP42AudioDecoder.h"
#import "MP42AudioEncoder.h"
#import "MP42AC3AudioEncoder.h"

#import "MP42Track+Private.h"
#import "MP42FileImporter.h"
#import "MP42FileImporter+Private.h"

#import <CoreAudio/CoreAudio.h>

@interface MP42AudioConverter ()

@property (nonatomic, readonly) MP42AudioDecoder *decoder;
@property (nonatomic, readonly) id<MP42AudioUnit> encoder;

@end

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42AudioConverter

#pragma mark - Init

- (instancetype)initWithTrack:(MP42AudioTrack *)track settings:(MP42AudioConversionSettings *)settings error:(NSError * __autoreleasing *)error
{
    self = [super init];

    if (self) {
        NSData *magicCookie = [track.importer magicCookieForTrack:track];
        AudioStreamBasicDescription asbd = [self basicDescriptorForTrack:track];
        UInt32 initialPadding = [self initialPaddingForTrack:track];
        UInt32 channelLayoutSize = sizeof(AudioChannelLayout);
        AudioChannelLayout *channelLayout = calloc(channelLayoutSize, 1);
        channelLayout->mChannelLayoutTag = track.channelLayoutTag;

        _decoder = [[MP42AudioDecoder alloc] initWithAudioFormat:asbd
                                                   channelLayout:channelLayout
                                               channelLayoutSize:channelLayoutSize
                                                     mixdownType:settings.mixDown
                                                             drc:settings.drc
                                                  initialPadding:initialPadding
                                                     magicCookie:magicCookie error:error];

        free(channelLayout);

        if (!_decoder) {
            return nil;
        }

        if (settings.format == kMP42AudioCodecType_AC3 || settings.format == kMP42AudioCodecType_EnhancedAC3) {
            _encoder = [[MP42AC3AudioEncoder alloc] initWithInputUnit:_decoder
                                                              bitRate:settings.bitRate
                                                                error:error];
        }
        else {
            _encoder = [[MP42AudioEncoder alloc] initWithInputUnit:_decoder
                                                           bitRate:settings.bitRate
                                                             error:error];
        }
        _encoder.outputUnit = self;
        _encoder.outputType = MP42AudioUnitOutputPull;

        if (!_encoder) {
            return nil;
        }
    }

    return self;
}

- (UInt32)initialPaddingForTrack:(MP42AudioTrack *)track
{
    UInt32 initialPadding = 0;
    if (track.format == kMP42AudioCodecType_MPEG4AAC ||
        track.format == kMP42AudioCodecType_MPEG4AAC_HE ||
        track.format == kMP42AudioCodecType_MPEG4AAC_HE_V2) {
        initialPadding = 2112;
    }
    else if (track.format == kMP42AudioCodecType_AC3 ||
             track.format == kMP42AudioCodecType_EnhancedAC3) {
        initialPadding = 256;
    }
    else if (track.format == kMP42AudioCodecType_MPEGLayer3) {
        initialPadding = 1105;
    }

    return initialPadding;
}

- (AudioStreamBasicDescription)basicDescriptorForTrack:(MP42AudioTrack *)track
{
    AudioStreamBasicDescription asbd;
    bzero(&asbd, sizeof(AudioStreamBasicDescription));
    asbd.mSampleRate = track.timescale;
    asbd.mChannelsPerFrame = track.channels;

    if (track.format == kMP42AudioCodecType_LinearPCM) {
        AudioStreamBasicDescription temp = [track.importer audioDescriptionForTrack:track];
        if (temp.mFormatID) {
            asbd = temp;
        }
        else {
            asbd.mFormatID = kAudioFormatLinearPCM;
        }
    }
    else {
        asbd.mFormatID = track.format;
    }

    return asbd;
}

- (void)addSample:(MP42SampleBuffer *)sample
{
    [_decoder addSample:sample];
}

- (MP42SampleBuffer *)copyEncodedSample
{
    return [_encoder copyEncodedSample];
}

- (nullable NSData *)magicCookie {
    return _encoder.magicCookie;
}

- (double)sampleRate {
    double sampleRate = self.decoder.outputFormat.mSampleRate;
    if (sampleRate > 48000) {
        return 48000;
    }
    return sampleRate;
}

@end
