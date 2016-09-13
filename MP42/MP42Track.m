//
//  MP42Track.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import "MP42Track.h"
#import "MP42PrivateUtilities.h"
#import "MP42Utilities.h"
#import "MP42FileImporter.h"
#import "MP42Sample.h"
#import "MP42Fifo.h"
#import "MP42Languages.h"

#import "MP42Track+Private.h"

@interface MP42Track ()
{
    NSString *_name;
    NSString *_language;
    NSString *_extendedLanguageTag;

    BOOL        _enabled;
    uint64_t    _alternate_group;
    int64_t     _startOffset;
}

@property(nonatomic, readwrite) MP42TrackId trackId;
@property(nonatomic, readwrite) MP42TrackId sourceId;

@property(nonatomic, readwrite, copy) NSURL *URL;

@property(nonatomic, readwrite) FourCharCode format;
@property(nonatomic, readwrite) MP42MediaType mediaType;

@property(nonatomic, readwrite) MP42Duration duration;
@property(nonatomic, readwrite) uint64_t dataLength;

@property(nonatomic, readwrite) BOOL muxed;

@property(nonatomic, readwrite) BOOL isEdited;
@property(nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *updatedProperty;

@end

@implementation MP42Track

- (instancetype)init
{
    if ((self = [super init])) {
        _enabled = YES;
        _updatedProperty = [[NSMutableDictionary alloc] init];
        _mediaCharacteristicTags = [[NSSet alloc] init];
        _language = @"Unknown";
    }
    return self;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP4FileHandle)fileHandle
{
	if ((self = [super init])) {
        _URL = URL;
		_trackId = (MP4TrackId)trackID;
        _isEdited = NO;
        _muxed = YES;
        _updatedProperty = [[NSMutableDictionary alloc] init];

        if (fileHandle) {
            _format = getTrackMediaSubType(fileHandle, _trackId);
            _mediaType = getTrackMediaType(fileHandle, _trackId);

            NSString *trackName = getTrackName(fileHandle, _trackId);
            if (trackName) {
                _name = [trackName copy];
            }
            _language = getHumanReadableTrackLanguage(fileHandle, _trackId);

            // Extended language tag
            if (MP4HaveTrackAtom(fileHandle, _trackId, "mdia.elng")) {
                const char *elng;
                if (MP4GetTrackStringProperty(fileHandle, _trackId, "mdia.elng", &elng)) {
                    _extendedLanguageTag = [NSString stringWithCString:elng encoding:NSASCIIStringEncoding];
                }
            }

            _bitrate = MP4GetTrackBitRate(fileHandle, _trackId);
            _duration = MP4ConvertFromTrackDuration(fileHandle, _trackId,
                                                   MP4GetTrackDuration(fileHandle, _trackId),
                                                   MP4_MSECS_TIME_SCALE);
            _timescale = MP4GetTrackTimeScale(fileHandle, _trackId);
            _startOffset = getTrackStartOffset(fileHandle, _trackId);

            _dataLength = getTrackSize(fileHandle, _trackId);

            // Track flags
            uint64_t temp;
            MP4GetTrackIntegerProperty(fileHandle, _trackId, "tkhd.flags", &temp);
            if (temp & TRACK_ENABLED) {
                _enabled = YES;
            }
            else {
                _enabled = NO;
            }

            MP4GetTrackIntegerProperty(fileHandle, _trackId, "tkhd.alternate_group", &_alternate_group);

            // Media characteristic tags
            NSMutableSet *mediaCharacteristicTags = [[NSMutableSet alloc] init];

            BOOL found = YES;
            NSUInteger count = 0;

            while (found) {
                NSString *atomName = [NSString stringWithFormat:@"udta.tagc[%lu]", (unsigned long)count];

                if (MP4HaveTrackAtom(fileHandle, _trackId, atomName.UTF8String)) {
                    uint8_t   *ppValue;
                    uint32_t  pValueSize;
                    NSString *propertyName = [atomName stringByAppendingString:@".tag"];

                    MP4GetTrackBytesProperty(fileHandle, _trackId, propertyName.UTF8String, &ppValue, &pValueSize);

                    if (pValueSize) {
                        NSString *tag = [[NSString alloc] initWithBytes:ppValue length:pValueSize encoding:NSASCIIStringEncoding];
                        if (tag) {
                            [mediaCharacteristicTags addObject:tag];
                        }
                    }

                    count++;
                }
                else {
                    found = NO;
                }
            }

            _mediaCharacteristicTags = [mediaCharacteristicTags copy];
        }
	}

    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Track: %d, %@, %@, %llu kbit/s, %@", self.trackId, self.name, self.timeString, self.dataLength / self.duration * 8, localizedDisplayName(self.mediaType, self.format)];
}

- (void)dealloc {
    free(_helper);
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    MP42Track *copy = [[[self class] alloc] init];

    if (copy) {
        copy->_trackId = _trackId;
        copy->_sourceId = _sourceId;

        copy->_URL = _URL;
        copy->_format = _format;
        copy->_mediaType = _mediaType;
        copy->_name = [_name copy];
        copy->_language = [_language copy];
        copy->_extendedLanguageTag = [_extendedLanguageTag copy];
        copy->_enabled = _enabled;
        copy->_alternate_group = _alternate_group;
        copy->_startOffset = _startOffset;

        copy->_dataLength = _dataLength;

        copy->_timescale = _timescale;
        copy->_bitrate = _bitrate;
        copy->_duration = _duration;

        copy->_conversionSettings = [_conversionSettings copy];

        copy->_updatedProperty = [_updatedProperty mutableCopy];

        copy->_mediaCharacteristicTags = [_mediaCharacteristicTags copy];

        if (_helper) {
            copy->_helper = [self copy_muxer_helper];
        }
    }

    return copy;
}

- (BOOL)writeToFile:(MP4FileHandle)fileHandle error:(NSError **)outError
{
    BOOL success = YES;

    if (!fileHandle || !_trackId) {
        if ( outError != NULL) {
            *outError = MP42Error(@"Failed to modify track",
                                  nil,
                                  120);
            return NO;

        }
    }

    if (_updatedProperty[@"name"] || !_muxed) {
        if (_name != nil && ![_name isEqualToString:self.defaultName]) {
            MP4SetTrackName(fileHandle, _trackId, _name.UTF8String);
        }
        else {
            MP4SetTrackName(fileHandle, _trackId, "\0");
        }
    }

    if (_updatedProperty[@"alternate_group"] || !_muxed) {
        MP4SetTrackIntegerProperty(fileHandle, _trackId, "tkhd.alternate_group", _alternate_group);
    }

    if (_updatedProperty[@"start_offset"]) {
        setTrackStartOffset(fileHandle, _trackId, _startOffset);
    }

    if (_updatedProperty[@"language"] || !_muxed) {
        MP4SetTrackLanguage(fileHandle, _trackId, lang_for_english(_language.UTF8String)->iso639_2);
    }

    if ((_updatedProperty[@"extendedLanguageTag"] || !_muxed) && _extendedLanguageTag) {
        MP4SetTrackStringProperty(fileHandle, _trackId, "mdia.elng", [_extendedLanguageTag cStringUsingEncoding:NSASCIIStringEncoding]);
    }

    if (_updatedProperty[@"enabled"] || !_muxed) {
        if (_enabled) { MP4SetTrackEnabled(fileHandle, _trackId); }
        else { MP4SetTrackDisabled(fileHandle, _trackId); }
    }

    if (_updatedProperty[@"mediaCharacteristicTags"] || !_muxed) {
        MP4RemoveAllMediaCharacteristicTags(fileHandle, _trackId);

        for (NSString *tag in _mediaCharacteristicTags) {
            MP4AddMediaCharacteristicTag(fileHandle, _trackId, tag.UTF8String);
        }
    }

    return success;
}

- (void *)muxer_helper
{
    if (_helper == NULL) {
        _helper = [self create_muxer_helper];
    }

    return _helper;
}

- (NSString *)timeString
{
    return StringFromTime(_duration, 1000);
}

- (NSString *)name {
    if (_name == nil) {
        _name = [[self defaultName] copy];
    }
    return [_name copy];
}

- (NSString *)defaultName {
    return localizedMediaDisplayName(_mediaType);
}

- (void)setName:(NSString *)newName
{
    if (newName.length) {
        _name = [newName copy];
    }
    else {
        _name = [self defaultName];
    }

    self.isEdited = YES;
    _updatedProperty[@"name"] = @YES;

}

- (NSString *)language {
    return _language;
}

- (void)setLanguage:(NSString *)newLang
{
    _language = [newLang copy];
    self.isEdited = YES;
    _updatedProperty[@"language"] = @YES;

}

- (NSString *)extendedLanguageTag {
    return [_extendedLanguageTag copy];
}

- (void)setExtendedLanguageTag:(NSString *)newExtendedLanguageTag
{
    _extendedLanguageTag = [newExtendedLanguageTag copy];
    self.isEdited = YES;
    _updatedProperty[@"extendedLanguageTag"] = @YES;
}

- (void)setMediaCharacteristicTags:(NSSet<NSString *> *)mediaCharacteristicTags
{
    _mediaCharacteristicTags = [mediaCharacteristicTags copy];
    self.isEdited = YES;
    _updatedProperty[@"mediaCharacteristicTags"] = @YES;
}

- (void)setEnabled:(BOOL)newState
{
    if (_enabled != newState) {
        _enabled = newState;
        self.isEdited = YES;
        _updatedProperty[@"enabled"] = @YES;
    }
}

- (BOOL)isEnabled {
    return _enabled;
}

- (uint64_t)alternate_group {
    return _alternate_group;
}

- (void)setAlternate_group:(uint64_t)newGroup
{
    _alternate_group = newGroup;
    self.isEdited = YES;
    _updatedProperty[@"alternate_group"] = @YES;
}

- (int64_t)startOffset {
    return _startOffset;
}

- (void)setStartOffset:(int64_t)newOffset
{
    _startOffset = newOffset;
    self.isEdited = YES;
    _updatedProperty[@"start_offset"] = @YES;
}

- (NSString *)formatSummary
{
    if (self.conversionSettings) {
        return localizedDisplayName(_mediaType, self.conversionSettings.format);
    }
    else {
        return localizedDisplayName(_mediaType, _format);
    }
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt:3 forKey:@"MP42TrackVersion"];

    [coder encodeInt64:_trackId forKey:@"Id"];
    [coder encodeInt64:_sourceId forKey:@"sourceId"];

#ifdef SB_SANDBOX
    if ([sourceURL respondsToSelector:@selector(startAccessingSecurityScopedResource)]) {
        NSData *bookmarkData = nil;
        NSError *error = nil;
        bookmarkData = [sourceURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                         includingResourceValuesForKeys:nil
                                          relativeToURL:nil // Make it app-scoped
                                                  error:&error];
        if (error) {
            NSLog(@"Error creating bookmark for URL (%@): %@", sourceURL, error);
        }
        
        [coder encodeObject:bookmarkData forKey:@"bookmark"];
    }
    else {
        [coder encodeObject:sourceURL forKey:@"sourceURL"];
    }
#else
    [coder encodeObject:_URL forKey:@"sourceURL"];
#endif

    [coder encodeInteger:_format forKey:@"format"];
    [coder encodeInteger:_mediaType forKey:@"mediaType"];
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_language forKey:@"language"];
    [coder encodeObject:_extendedLanguageTag forKey:@"extendedLanguageTag"];

    [coder encodeBool:_enabled forKey:@"enabled"];

    [coder encodeInt64:_alternate_group forKey:@"alternate_group"];
    [coder encodeInt64:_startOffset forKey:@"startOffset"];

    [coder encodeBool:_isEdited forKey:@"isEdited"];
    [coder encodeBool:_muxed forKey:@"muxed"];
    [coder encodeObject:_conversionSettings forKey:@"conversionSettings"];

    [coder encodeInt32:_timescale forKey:@"timescale"];
    [coder encodeInt32:_bitrate forKey:@"bitrate"];
    [coder encodeInt64:_duration forKey:@"duration"];
    
    [coder encodeInt64:_dataLength forKey:@"dataLength"];

    [coder encodeObject:_updatedProperty forKey:@"updatedProperty"];
    [coder encodeObject:_mediaCharacteristicTags forKey:@"mediaCharacteristicTags"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    NSInteger version = [decoder decodeInt32ForKey:@"MP42TrackVersion"];

    _trackId = (MP4TrackId)[decoder decodeInt64ForKey:@"Id"];
    _sourceId = (MP4TrackId)[decoder decodeInt64ForKey:@"sourceId"];

    NSData *bookmarkData = [decoder decodeObjectOfClass:[NSData class] forKey:@"bookmark"];
    if (bookmarkData) {
        BOOL bookmarkDataIsStale;
        NSError *error;
        _URL = [NSURL
                    URLByResolvingBookmarkData:bookmarkData
                    options:NSURLBookmarkResolutionWithSecurityScope
                    relativeToURL:nil
                    bookmarkDataIsStale:&bookmarkDataIsStale
                    error:&error];
    } else {
        _URL = [decoder decodeObjectOfClass:[NSURL class] forKey:@"sourceURL"];
    }

    _format = [decoder decodeIntegerForKey:@"format"];
    _mediaType = [decoder decodeIntegerForKey:@"mediaType"];
    _name = [decoder decodeObjectOfClass:[NSString class] forKey:@"name"];
    _language = [decoder decodeObjectOfClass:[NSString class] forKey:@"language"];
    _extendedLanguageTag = [decoder decodeObjectOfClass:[NSString class] forKey:@"extendedLanguageTag"];

    _enabled = [decoder decodeBoolForKey:@"enabled"];

    _alternate_group = [decoder decodeInt64ForKey:@"alternate_group"];
    _startOffset = [decoder decodeInt64ForKey:@"startOffset"];

    _isEdited = [decoder decodeBoolForKey:@"isEdited"];
    _muxed = [decoder decodeBoolForKey:@"muxed"];
    _conversionSettings = [decoder decodeObjectOfClass:[MP42ConversionSettings class] forKey:@"conversionSettings"];

    _timescale = [decoder decodeInt32ForKey:@"timescale"];
    _bitrate = [decoder decodeInt32ForKey:@"bitrate"];
    _duration = [decoder decodeInt64ForKey:@"duration"];
    
    if (version == 2) {
        _dataLength = [decoder decodeInt64ForKey:@"dataLength"];
    }

    _updatedProperty = [decoder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"updatedProperty"];
    _mediaCharacteristicTags = [decoder decodeObjectOfClass:[NSSet class] forKey:@"mediaCharacteristicTags"];

    return self;
}

@end
