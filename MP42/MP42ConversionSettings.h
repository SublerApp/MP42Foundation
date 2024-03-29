//
//  MP42ConversionSettings.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 12/09/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42MediaFormat.h>

NS_ASSUME_NONNULL_BEGIN

@interface MP42ConversionSettings : NSObject <NSCopying, NSSecureCoding>

+ (instancetype)subtitlesConversion;

@property (nonatomic, readonly) FourCharCode format;

@end

@interface MP42AudioConversionSettings : MP42ConversionSettings <NSCopying, NSSecureCoding>

+ (instancetype)audioConversionWithBitRate:(UInt32)bitrate mixDown:(MP42AudioMixdown)mixDown drc:(float)drc;

- (instancetype)initWithFormat:(FourCharCode)format bitRate:(UInt32)bitRate mixDown:(MP42AudioMixdown)mixDown drc:(float)drc;

@property (nonatomic, readonly) UInt32 bitRate;

@property (nonatomic, readonly) MP42AudioMixdown mixDown;
@property (nonatomic, readonly) float drc;

@end

@interface MP42RawConversionSettings : MP42ConversionSettings <NSCopying, NSSecureCoding>

+ (instancetype)rawConversionWithFrameRate:(NSUInteger)frameRate;

@property (nonatomic, readonly) NSUInteger frameRate;

@end

NS_ASSUME_NONNULL_END
