//
//  MP42AudioDecoder.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MP42AudioUnit.h"

@class MP42SampleBuffer;
@class MP42AudioTrack;

NS_ASSUME_NONNULL_BEGIN

@interface MP42AudioDecoder : NSObject<MP42AudioUnit>

- (instancetype)initWithAudioFormat:(AudioStreamBasicDescription)asbd mixdownType:(NSString *)mixdownType magicCookie:(NSData *)magicCookie error:(NSError **)error;

@property (nonatomic, readonly) AudioStreamBasicDescription inputFormat;
@property (nonatomic, readonly) AudioStreamBasicDescription outputFormat;

- (void)addSample:(MP42SampleBuffer *)sample;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END