//
//  MP42AudioDecoder.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42MediaFormat.h"
#import "MP42AudioUnit.h"

@class MP42SampleBuffer;
@class MP42AudioTrack;

NS_ASSUME_NONNULL_BEGIN

@interface MP42AudioDecoder : NSObject<MP42AudioUnit>

- (instancetype)initWithAudioFormat:(AudioStreamBasicDescription)asbd
                      channelLayout:(AudioChannelLayout *)channelLayout
                  channelLayoutSize:(UInt32)channelLayoutSize
                        mixdownType:(MP42AudioMixdown)mixdownType
                                drc:(float)drc
                     initialPadding:(UInt32)initialPadding
                        magicCookie:(nullable NSData *)magicCookie
                              error:(NSError * __autoreleasing *)error;

@property (nonatomic, readonly, nullable) AudioChannelLayout *inputLayout;
@property (nonatomic, readonly) UInt32 inputLayoutSize;
@property (nonatomic, readonly) AudioStreamBasicDescription inputFormat;

@property (nonatomic, readonly, nullable) AudioChannelLayout *outputLayout;
@property (nonatomic, readonly) UInt32 outputLayoutSize;
@property (nonatomic, readonly) AudioStreamBasicDescription outputFormat;

@end

NS_ASSUME_NONNULL_END
