//
//  MP42Track.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42MediaFormat.h"

/**
 *  MP42Track
 */
@interface MP42Track : NSObject <NSCoding, NSCopying> {
@protected
    MP42TrackId  _Id;
    MP42TrackId  _sourceId;

    NSURL       *_sourceURL;
    NSString    *_format;
    NSString    *_sourceFormat;
    NSString    *_mediaType;

    NSString    *_name;
    NSString    *_language;

    BOOL        _enabled;
    uint64_t    _alternate_group;
    int64_t     _startOffset;

    BOOL    _isEdited;
    BOOL    _muxed;
    BOOL    _needConversion;

    uint64_t    _size;
	uint32_t    _timescale;
	uint32_t    _bitrate;
	MP42Duration _duration;

    NSMutableDictionary *_updatedProperty;

    void *_helper;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle;

- (BOOL)writeToFile:(MP42FileHandle)fileHandle error:(NSError **)outError;

- (NSString *)timeString;
- (NSString *)formatSummary;

@property(nonatomic, readwrite) MP42TrackId Id;
@property(nonatomic, readwrite) MP42TrackId sourceId;

@property(nonatomic, readwrite, retain) NSURL *sourceURL;
@property(nonatomic, readwrite, retain) NSString *format;
@property(nonatomic, readwrite, retain) NSString *sourceFormat;
@property(nonatomic, readonly, retain) NSString *mediaType;

@property(nonatomic, readwrite, retain) NSString *name;
@property(nonatomic, readwrite, retain) NSString *language;
@property(nonatomic, readwrite, retain) NSString *extendedLanguageTag;

@property(nonatomic, readwrite) BOOL     enabled;
@property(nonatomic, readwrite) uint64_t alternate_group;
@property(nonatomic, readwrite) int64_t  startOffset;

@property(nonatomic, readonly)  uint32_t timescale;
@property(nonatomic, readonly)  uint32_t bitrate;
@property(nonatomic, readwrite) MP42Duration duration;

@property(nonatomic, readwrite) BOOL isEdited;
@property(nonatomic, readwrite) BOOL muxed;
@property(nonatomic, readwrite) BOOL needConversion;

@property(nonatomic, readwrite) uint64_t dataLength;

@end
