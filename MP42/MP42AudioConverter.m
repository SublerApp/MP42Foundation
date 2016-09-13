//
//  SBAudioConverter.m
//  Subler
//
//  Created by Damiano Galassi on 16/09/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import "MP42AudioConverter.h"
#import "MP42AudioTrack.h"
#import "MP42MediaFormat.h"
#import "MP42Fifo.h"

#import "MP42AudioDecoder.h"
#import "MP42AudioEncoder.h"

#import "MP42Track+Muxer.h"
#import "MP42FileImporter+Private.h"

#import <CoreAudio/CoreAudio.h>

@interface MP42AudioConverter ()

@property (nonatomic, readonly) MP42AudioDecoder *decoder;
@property (nonatomic, readonly) MP42AudioEncoder *encoder;

@end

@implementation MP42AudioConverter

#pragma mark - Init

- (instancetype)initWithTrack:(MP42AudioTrack *)track settings:(MP42ConversionSettings *)settings error:(NSError **)error
{
    self = [super init];

    if (self) {
        NSData *magicCookie = [track.muxer_helper->importer magicCookieForTrack:track];
        AudioStreamBasicDescription asbd = [self basicDescriptorForTrack:track];

        _decoder = [[MP42AudioDecoder alloc] initWithAudioFormat:asbd
                                                     mixdownType:settings.mixDown
                                                             drc:settings.drc
                                                     magicCookie:magicCookie error:error];

        if (!_decoder) {
            return nil;
        }

        _encoder = [[MP42AudioEncoder alloc] initWithInputUnit:_decoder
                                                       bitRate:settings.bitRate
                                                         error:error];
        _encoder.outputUnit = self;
        _encoder.outputType = MP42AudioUnitOutputPull;

        if (!_encoder) {
            return nil;
        }
    }

    return self;
}

- (AudioStreamBasicDescription)basicDescriptorForTrack:(MP42AudioTrack *)track
{
    AudioStreamBasicDescription asbd;
    bzero(&asbd, sizeof(AudioStreamBasicDescription));
    asbd.mSampleRate = [track.muxer_helper->importer timescaleForTrack:track];;
    asbd.mChannelsPerFrame = track.channels;

    if (track.format == kMP42AudioCodecType_LinearPCM) {
        AudioStreamBasicDescription temp = [track.muxer_helper->importer audioDescriptionForTrack:track];
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

- (NSData *)magicCookie {
    return _encoder.magicCookie;
}

- (double)sampleRate {
    double sampleRate = self.decoder.outputFormat.mSampleRate;
    if (sampleRate > 48000) {
        return 48000;
    }
    return sampleRate;
}

- (void)dealloc {
    [_decoder release];
    [_encoder release];

    [super dealloc];
}

@end
