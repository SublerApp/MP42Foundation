//
//  MP42AudioConverter.h
//  Subler
//
//  Created by Damiano Galassi on 16/09/10.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42ConverterProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42AudioTrack;
@class MP42AudioConversionSettings;

@interface MP42AudioConverter : NSObject <MP42ConverterProtocol>

- (instancetype)initWithTrack:(MP42AudioTrack *)track settings:(MP42AudioConversionSettings *)settings error:(NSError * __autoreleasing *)error;

- (void)addSample:(MP42SampleBuffer *)sample;
- (nullable MP42SampleBuffer *)copyEncodedSample;

@property (nonatomic, readonly, nullable) NSData *magicCookie;
@property (nonatomic, readonly) double sampleRate;

NS_ASSUME_NONNULL_END

@end
