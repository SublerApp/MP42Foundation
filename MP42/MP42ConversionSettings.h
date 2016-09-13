//
//  MP42ConversionSettings.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 12/09/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MP42ConversionSettings : NSObject <NSCopying, NSSecureCoding>

+ (instancetype)audioConversionWithBitRate:(NSUInteger)bitrate mixDown:(NSString *)mixDown drc:(float)drc;
+ (instancetype)subtitlesConversion;

@property (nonatomic, readonly) FourCharCode format;
@property (nonatomic, readonly) NSUInteger   bitRate;

@property (nonatomic, readonly) NSString    *mixDown;
@property (nonatomic, readonly) float drc;

@end

NS_ASSUME_NONNULL_END
