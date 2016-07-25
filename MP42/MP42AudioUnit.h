//
//  MP42AudioUnit.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 24/07/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "MP42ConverterProtocol.h"

typedef NS_ENUM(NSUInteger, MP42AudioUnitOutput) {
    MP42AudioUnitOutputPush,
    MP42AudioUnitOutputPull,
};

@protocol MP42AudioUnit <MP42ConverterProtocol>

@property (nonatomic, readwrite) MP42AudioUnitOutput outputType;
@property (nonatomic, readwrite, unsafe_unretained) id<MP42ConverterProtocol> outputUnit;

@property (nonatomic, readonly) AudioStreamBasicDescription inputFormat;
@property (nonatomic, readonly) AudioStreamBasicDescription outputFormat;

@end
