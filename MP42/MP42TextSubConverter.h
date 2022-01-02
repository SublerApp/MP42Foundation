//
//  MP42TextSubConverter.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42ConverterProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42SubtitleTrack;

/**
 Converts Sub Station Alpha subtitles to Text subtitles (plus html tags).
 */
@interface MP42TextSubConverter : NSObject <MP42ConverterProtocol>

- (nullable instancetype)initWithTrack:(MP42SubtitleTrack *)track error:(NSError * __autoreleasing *)outError;

- (void)addSample:(MP42SampleBuffer *)sample;
- (nullable MP42SampleBuffer *)copyEncodedSample;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
