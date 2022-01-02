//
//  MP42ConversionSettings.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 12/09/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42ConversionSettings.h"
#import "MP42MediaFormat.h"

@implementation MP42ConversionSettings

+ (instancetype)subtitlesConversion
{
    return [[MP42ConversionSettings alloc] initWitFormat:kMP42SubtitleCodecType_3GText];
}

- (instancetype)initWitFormat:(FourCharCode)format
{
    self = [super init];
    if (self) {
        _format = format;
    }
    return self;
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    MP42ConversionSettings *copy = [[[self class] alloc] init];

    if (copy) {
        copy->_format = _format;
    }
    
    return copy;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt:1 forKey:@"MP42ConversionSettingsVersion"];
    [coder encodeInt32:_format forKey:@"format"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    _format = [decoder decodeInt32ForKey:@"format"];

    return self;
}

@end

@implementation MP42AudioConversionSettings

+ (instancetype)audioConversionWithBitRate:(UInt32)bitRate mixDown:(MP42AudioMixdown)mixDown drc:(float)drc
{
    return [[MP42AudioConversionSettings alloc] initWithFormat:kMP42AudioCodecType_MPEG4AAC bitRate:bitRate mixDown:mixDown drc:drc];
}

- (instancetype)initWithFormat:(FourCharCode)format bitRate:(UInt32)bitRate mixDown:(MP42AudioMixdown)mixDown drc:(float)drc
{
    self = [super initWitFormat:format];
    if (self) {
        _bitRate = bitRate;
        _mixDown = mixDown;
        _drc = drc;
    }
    return self;
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    MP42AudioConversionSettings *copy = [super copyWithZone:zone];

    if (copy) {
        copy->_bitRate = _bitRate;
        copy->_mixDown = _mixDown;
        copy->_drc = _drc;
    }

    return copy;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt32:_bitRate forKey:@"bitRate"];
    [coder encodeInt32:_mixDown forKey:@"mixDownType"];
    [coder encodeFloat:_drc forKey:@"drc"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    _bitRate = [decoder decodeInt32ForKey:@"bitRate"];
    _mixDown = [decoder decodeInt32ForKey:@"mixDownType"];
    _drc = [decoder decodeFloatForKey:@"drc"];

    return self;
}

@end

@implementation MP42RawConversionSettings

+ (instancetype)rawConversionWithFrameRate:(NSUInteger)frameRate
{
    return [[MP42RawConversionSettings alloc] initWitFormat:kMP42VideoCodecType_H264 frameRate:frameRate];
}

- (instancetype)initWitFormat:(FourCharCode)format frameRate:(NSUInteger)frameRate
{
    self = [super initWitFormat:format];
    if (self) {
        _frameRate = frameRate;
    }
    return self;
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    MP42RawConversionSettings *copy = [super copyWithZone:zone];

    if (copy) {
        copy->_frameRate = _frameRate;
    }

    return copy;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_frameRate forKey:@"frameRate"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    _frameRate = [decoder decodeIntegerForKey:@"frameRate"];

    return self;
}

@end

