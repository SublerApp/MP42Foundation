//
//  SBVobSubConverter.h
//  Subler
//
//  Created by Damiano Galassi on 26/03/11.
//  Copyright 2011 Damiano Galassi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MP42ConverterProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42SubtitleTrack;

@interface MP42BitmapSubConverter : NSObject <MP42ConverterProtocol>

- (instancetype)initWithTrack:(MP42SubtitleTrack *)track error:(NSError **)outError;

- (void)addSample:(MP42SampleBuffer *)sample;
- (nullable MP42SampleBuffer *)copyEncodedSample;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
