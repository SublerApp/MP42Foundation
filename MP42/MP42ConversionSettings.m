//
//  MP42ConversionSettings.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 12/09/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
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
    [coder encodeInteger:_format forKey:@"format"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    _format = [decoder decodeIntegerForKey:@"format"];

    return self;
}

@end

@implementation MP42AudioConversionSettings

+ (instancetype)audioConversionWithBitRate:(NSUInteger)bitRate mixDown:(NSString *)mixDown drc:(float)drc
{
    return [[MP42AudioConversionSettings alloc] initWitFormat:kMP42AudioCodecType_MPEG4AAC bitRate:bitRate mixDown:mixDown drc:drc];
}

- (instancetype)initWitFormat:(FourCharCode)format bitRate:(NSUInteger)bitRate mixDown:(NSString *)mixDown drc:(float)drc
{
    self = [super initWitFormat:format];
    if (self) {
        _bitRate = bitRate;
        _mixDown = [mixDown copy];
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
        copy->_mixDown = [_mixDown copy];
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
    [coder encodeInteger:_bitRate forKey:@"bitRate"];
    [coder encodeObject:_mixDown forKey:@"mixDown"];
    [coder encodeFloat:_drc forKey:@"drc"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    _bitRate = [decoder decodeIntegerForKey:@"bitRate"];
    _mixDown = [decoder decodeObjectOfClass:[NSString class] forKey:@"mixDown"];
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

