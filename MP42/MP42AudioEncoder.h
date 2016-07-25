//
//  MP42AudioEncoder.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MP42AudioUnit.h"

@class MP42SampleBuffer;

NS_ASSUME_NONNULL_BEGIN

@interface MP42AudioEncoder : NSObject<MP42AudioUnit>

- (instancetype)initWithInputUnit:(id<MP42AudioUnit>)unit bitRate:(NSUInteger)bitRate error:(NSError **)error;

@property (nonatomic, readonly) AudioStreamBasicDescription inputFormat;
@property (nonatomic, readonly) AudioStreamBasicDescription outputFormat;
@property (nonatomic, readonly) NSData *magicCookie;

- (void)addSample:(MP42SampleBuffer *)sample;

@end

NS_ASSUME_NONNULL_END
