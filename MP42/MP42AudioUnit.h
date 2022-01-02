//
//  MP42AudioUnit.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 24/07/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "MP42ConverterProtocol.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MP42AudioUnitOutput) {
    MP42AudioUnitOutputPush,
    MP42AudioUnitOutputPull,
};

@protocol MP42AudioUnit <MP42ConverterProtocol>

- (void)reconfigure;

@property (nonatomic, readwrite) MP42AudioUnitOutput outputType;
@property (nonatomic, readwrite, unsafe_unretained) id<MP42ConverterProtocol> outputUnit;

@property (nonatomic, readonly, nullable) AudioChannelLayout *inputLayout;
@property (nonatomic, readonly) UInt32 inputLayoutSize;
@property (nonatomic, readonly) AudioStreamBasicDescription inputFormat;

@property (nonatomic, readonly, nullable) AudioChannelLayout *outputLayout;
@property (nonatomic, readonly) UInt32 outputLayoutSize;
@property (nonatomic, readonly) AudioStreamBasicDescription outputFormat;

@end

NS_ASSUME_NONNULL_END
