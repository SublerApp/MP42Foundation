//
//  MP42AC3AudioEncoder.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MP42AudioUnit.h"

@class MP42SampleBuffer;

NS_ASSUME_NONNULL_BEGIN

@interface MP42AC3AudioEncoder : NSObject<MP42AudioUnit>

- (instancetype)initWithInputUnit:(id<MP42AudioUnit>)unit bitRate:(NSUInteger)bitRate error:(NSError * __autoreleasing *)error;

@property (nonatomic, readonly, nullable) AudioChannelLayout *inputLayout;
@property (nonatomic, readonly) UInt32 inputLayoutSize;
@property (nonatomic, readonly) AudioStreamBasicDescription inputFormat;

@property (nonatomic, readonly, nullable) AudioChannelLayout *outputLayout;
@property (nonatomic, readonly) UInt32 outputLayoutSize;
@property (nonatomic, readonly) AudioStreamBasicDescription outputFormat;

@property (nonatomic, readonly, nullable) NSData *magicCookie;

@end

NS_ASSUME_NONNULL_END
