//
//  MP42Track.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42MediaFormat.h"
#import "MP42ConversionSettings.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  MP42Track
 */
@interface MP42Track : NSObject <NSSecureCoding, NSCopying> {
@protected
    MP42TrackId  _trackId;

    NSURL       *_sourceURL;
    FourCharCode   _format;
    MP42MediaType  _mediaType;

    NSString    *_language;
    NSString    *_extendedLanguageTag;

    BOOL        _enabled;

    BOOL    _isEdited;
    BOOL    _muxed;

    NSMutableDictionary<NSString *, NSNumber *> *_updatedProperty;
    void *_helper;
}

@property(nonatomic, readwrite) MP42TrackId trackId;
@property(nonatomic, readwrite) MP42TrackId sourceId;

@property(nonatomic, readwrite, copy) NSURL *sourceURL;
@property(nonatomic, readwrite) FourCharCode format;
@property(nonatomic, readonly) MP42MediaType mediaType;

@property(nonatomic, readwrite, copy) NSString *name;
@property(nonatomic, readwrite, copy) NSString *language;
@property(nonatomic, readwrite, copy) NSString *extendedLanguageTag;

@property(nonatomic, readwrite, copy) NSSet<NSString *> *mediaCharacteristicTags;

@property(nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, readwrite) uint64_t alternate_group;
@property(nonatomic, readwrite) int64_t  startOffset;

@property(nonatomic, readonly)  uint32_t timescale;
@property(nonatomic, readonly)  uint32_t bitrate;
@property(nonatomic, readwrite) MP42Duration duration;

@property(nonatomic, readwrite) BOOL isEdited;
@property(nonatomic, readwrite) BOOL muxed;

@property(nonatomic, readwrite, copy) MP42ConversionSettings *conversionSettings;

@property(nonatomic, readwrite) uint64_t dataLength;

@property (nonatomic, readonly) NSString *timeString;
@property (nonatomic, readonly) NSString *formatSummary;

@end

NS_ASSUME_NONNULL_END
