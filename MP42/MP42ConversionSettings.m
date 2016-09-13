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

+ (instancetype)audioConversionWithBitRate:(NSUInteger)bitRate mixDown:(NSString *)mixDown drc:(float)drc
{
    return [[MP42ConversionSettings alloc] initWitFormat:kMP42AudioCodecType_MPEG4AAC bitRate:bitRate mixDown:mixDown drc:drc];
}

+ (instancetype)subtitlesConversion
{
    return [[MP42ConversionSettings alloc] initWitFormat:kMP42SubtitleCodecType_3GText bitRate:0 mixDown:SBNoneMixdown drc:0];
}

- (instancetype)initWitFormat:(FourCharCode)format bitRate:(NSUInteger)bitRate mixDown:(NSString *)mixDown drc:(float)drc
{
    self = [super init];
    if (self) {
        _format = format;
        _bitRate = bitRate;
        _mixDown = [mixDown copy];
        _drc = drc;
    }
    return self;
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    MP42ConversionSettings *copy = [[[self class] alloc] init];

    if (copy) {
        copy->_format = _format;
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
    [coder encodeInt:1 forKey:@"MP42ConversionSettingsVersion"];

    [coder encodeInteger:_format forKey:@"format"];
    [coder encodeInteger:_bitRate forKey:@"bitRate"];
    [coder encodeObject:_mixDown forKey:@"mixDown"];
    [coder encodeFloat:_drc forKey:@"drc"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    _format = [decoder decodeIntegerForKey:@"format"];
    _bitRate = [decoder decodeIntegerForKey:@"bitRate"];
    _mixDown = [decoder decodeObjectOfClass:[NSString class] forKey:@"mixDown"];
    _drc = [decoder decodeFloatForKey:@"drc"];

    return self;
}

@end
