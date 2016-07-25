//
//  SBAudioConverter.h
//  Subler
//
//  Created by Damiano Galassi on 16/09/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "downmix.h"
#import "MP42ConverterProtocol.h"

#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42AudioTrack;

extern NSString * const SBMonoMixdown;
extern NSString * const SBStereoMixdown;
extern NSString * const SBDolbyMixdown;
extern NSString * const SBDolbyPlIIMixdown;

@interface MP42AudioConverter : NSObject <MP42ConverterProtocol>

- (instancetype)initWithTrack:(MP42AudioTrack *)track andMixdownType:(NSString *)mixdownType error:(NSError **)error;

- (void)addSample:(MP42SampleBuffer *)sample;
- (nullable MP42SampleBuffer *)copyEncodedSample;

- (NSData *)magicCookie;

- (void)cancel;

NS_ASSUME_NONNULL_END

@end
