//
//  MP42Track.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42MediaFormat.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  MP42Track
 */
@interface MP42Track : NSObject <NSCoding, NSCopying> {
@protected
    MP42TrackId  _trackId;
    MP42TrackId  _sourceId;

    NSURL       *_sourceURL;
    NSString    *_format;
    NSString    *_sourceFormat;
    NSString    *_mediaType;

    NSString    *_name;
    NSString    *_language;
    NSString    *_extendedLanguageTag;

    BOOL        _enabled;

    BOOL    _isEdited;
    BOOL    _muxed;
    BOOL    _needConversion;

    uint64_t    _size;
	uint32_t    _timescale;
	uint32_t    _bitrate;
	MP42Duration _duration;

    NSMutableDictionary<NSString *, NSNumber *> *_updatedProperty;

    @private
    NSSet<NSString *> *_mediaCharacteristicTags;

    uint64_t    _alternate_group;
    int64_t     _startOffset;

    void *_helper;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle;

- (BOOL)writeToFile:(MP42FileHandle)fileHandle error:(NSError **)outError;

@property(nonatomic, readwrite) MP42TrackId trackId;
@property(nonatomic, readwrite) MP42TrackId sourceId;

@property(nonatomic, readwrite, copy) NSURL *sourceURL;
@property(nonatomic, readwrite, copy) NSString *format;
@property(nonatomic, readwrite, copy) NSString *sourceFormat;
@property(nonatomic, readonly, copy) NSString *mediaType;

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
@property(nonatomic, readwrite) BOOL needConversion;

@property(nonatomic, readwrite) uint64_t dataLength;

@property (nonatomic, readonly) NSString *timeString;
@property (nonatomic, readonly) NSString *formatSummary;

@end

NS_ASSUME_NONNULL_END
