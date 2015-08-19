//
//  MP42Metadata.h
//  Subler
//
//  Created by Damiano Galassi on 06/02/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MP42MediaFormat.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42Image;

@interface MP42Metadata : NSObject <NSCoding, NSCopying> {
@private
    NSString                *presetName;
    NSMutableDictionary     *tagsDict;

    NSMutableArray<MP42Image *> *artworks;

    NSArray<NSURL *>        *artworkThumbURLs;
    NSArray<NSURL *>        *artworkFullsizeURLs;
    NSArray<NSString *>     *artworkProviderNames;

	NSString *ratingiTunesCode;

    uint8_t mediaKind;
    uint8_t contentRating;
    uint8_t hdVideo;
    uint8_t gapless;
    uint8_t podcast;

    BOOL isEdited;
    BOOL isArtworkEdited;
}

- (instancetype) initWithFileHandle:(MP42FileHandle)fileHandle;
- (instancetype) initWithFileURL:(NSURL *)URL;

- (NSArray *) availableMetadata;
- (NSArray *) writableMetadata;

- (NSArray *) availableGenres;

- (void) removeTagForKey:(NSString *)aKey;
- (BOOL) setTag:(id)value forKey:(NSString *)key;
- (BOOL) setMediaKindFromString:(NSString *)mediaKindString;
- (BOOL) setContentRatingFromString:(NSString *)contentRatingString;
- (BOOL) setArtworkFromFilePath:(NSString *)imageFilePath;

- (BOOL) writeMetadataWithFileHandle: (MP42FileHandle) fileHandle;

- (BOOL) mergeMetadata: (MP42Metadata *) newMetadata;

@property(nonatomic, readonly) NSMutableDictionary *tagsDict;

@property(nonatomic, readwrite, copy) NSString *presetName;

@property(nonatomic, readwrite, retain) NSMutableArray *artworks;

@property(nonatomic, readwrite, retain, nullable) NSArray<NSURL *> *artworkThumbURLs;
@property(nonatomic, readwrite, retain, nullable) NSArray<NSURL *> *artworkFullsizeURLs;
@property(nonatomic ,readwrite, retain, nullable) NSArray<NSString *> *artworkProviderNames;

@property(nonatomic, readwrite) uint8_t    mediaKind;
@property(nonatomic, readwrite) uint8_t    contentRating;
@property(nonatomic, readwrite) uint8_t    hdVideo;
@property(nonatomic, readwrite) uint8_t    gapless;
@property(nonatomic, readwrite) uint8_t    podcast;
@property(nonatomic, readwrite) BOOL       isEdited;
@property(nonatomic, readwrite) BOOL       isArtworkEdited;

@end

NS_ASSUME_NONNULL_END
