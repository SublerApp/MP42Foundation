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

- (instancetype)initWithTrack:(MP42AudioTrack *)track andMixdownType:(NSString *)mixdownType error:(NSError **)error {

    self = [super init];

    if (self) {
        NSData *magicCookie = [track.muxer_helper->importer magicCookieForTrack:track];
        UInt32 bitRate = [[[NSUserDefaults standardUserDefaults] valueForKey:@"SBAudioBitrate"] integerValue];
        AudioStreamBasicDescription asbd = [self basicDescriptorForTrack:track];

        _decoder = [[MP42AudioDecoder alloc] initWithAudioFormat:asbd
                                                     mixdownType:mixdownType
                                                             drc:1.5
                                                     magicCookie:magicCookie error:error];

        if (!_decoder) {
            return nil;
        }

        _encoder = [[MP42AudioEncoder alloc] initWithInputUnit:_decoder bitRate:bitRate error:error];
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
    asbd.mChannelsPerFrame = track.sourceChannels;

    NSString *format = track.sourceFormat;

    if ([format isEqualToString:MP42AudioFormatAAC]) {
        asbd.mFormatID = kAudioFormatMPEG4AAC;
    }
    else if ([format isEqualToString:MP42AudioFormatALAC]) {
        asbd.mFormatID = kAudioFormatAppleLossless;
    }
    else if ([format isEqualToString:MP42AudioFormatVorbis]) {
        asbd.mFormatID = 'XiVs';
    }
    else if ([format isEqualToString:MP42AudioFormatFLAC]) {
        asbd.mFormatID = 'XiFL';
    }
    else if ([format isEqualToString:MP42AudioFormatAC3]) {
        asbd.mFormatID = kAudioFormatAC3;
        asbd.mFramesPerPacket = 1536;
    }
    else if ([format isEqualToString:MP42AudioFormatEAC3]) {
        asbd.mFormatID = kAudioFormatEnhancedAC3;
        asbd.mFramesPerPacket = 1536;
    }
    else if ([format isEqualToString:MP42AudioFormatDTS]) {
        asbd.mFormatID = 'DTS ';
    }
    else if ([format isEqualToString:MP42AudioFormatMP1]) {
        asbd.mFormatID = kAudioFormatMPEGLayer1;
        asbd.mFramesPerPacket = 1152;
    }
    else if ([format isEqualToString:MP42AudioFormatMP2]) {
        asbd.mFormatID = kAudioFormatMPEGLayer2;
        asbd.mFramesPerPacket = 1152;
    }
    else if ([format isEqualToString:MP42AudioFormatMP3]) {
        asbd.mFormatID = kAudioFormatMPEGLayer3;
        asbd.mFramesPerPacket = 1152;
    }
    else if ([format isEqualToString:MP42AudioFormatTrueHD]) {
        asbd.mFormatID = 'trhd';
    }
    else if ([format isEqualToString:MP42AudioFormatOpus]) {
        asbd.mFormatID = 'Opus';
    }
    else if ([format isEqualToString:MP42AudioFormatPCM]) {
        AudioStreamBasicDescription temp = [track.muxer_helper->importer audioDescriptionForTrack:track];
        if (temp.mFormatID) {
            asbd = temp;
        }
        else {
            asbd.mFormatID = kAudioFormatLinearPCM;
        }
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

- (void)dealloc {
    [_decoder release];
    [_encoder release];

    [super dealloc];
}

@end
