//
//  MP42Metadata.h
//  Subler
//
//  Created by Damiano Galassi on 06/02/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42MediaFormat.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42Image;

@interface MP42Metadata : NSObject <NSCoding, NSCopying> {
@private
    NSString *presetName;
    NSMutableDictionary<NSString *, id> *tagsDict;

    NSMutableArray<MP42Image *> *artworks;

	NSString *ratingiTunesCode;

    uint8_t mediaKind;
    uint8_t contentRating;
    uint8_t hdVideo;
    uint8_t gapless;
    uint8_t podcast;

    BOOL isEdited;
    BOOL isArtworkEdited;
}

/**
 *  Initializes a new metadata instance by a given URL
 *
 *  @param URL An URL that identifies an xml file.
 *
 *  @return The receiver, initialized with the resource specified by URL.
 */
- (instancetype)initWithFileURL:(NSURL *)URL;

/**
 *  Returns the complete list of available metadata.
 */
+ (NSArray<NSString *> *) availableMetadata;

/**
 *  Returns the complete list of writable metadata.
 */
- (NSArray<NSString *> *) writableMetadata;

/**
 *  Returns the list of the available genres.
 */
- (NSArray<NSString *> *) availableGenres;


- (void)removeTagForKey:(NSString *)aKey;
- (BOOL)setTag:(id)value forKey:(NSString *)key;

- (nullable id)objectForKeyedSubscript:(NSString *)key;
- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key;

@property(nonatomic, readonly) NSMutableDictionary<NSString *, id> *tagsDict;

/**
 *  Merges the tags of the passed MP42Metadata instance.
 *
 *  @param metadata the instance to marge.
 */
- (void)mergeMetadata:(MP42Metadata *)metadata;


@property(nonatomic, readwrite) uint8_t    mediaKind;
@property(nonatomic, readwrite) uint8_t    contentRating;
@property(nonatomic, readwrite) uint8_t    hdVideo;
@property(nonatomic, readwrite) uint8_t    gapless;
@property(nonatomic, readwrite) uint8_t    podcast;

@property(nonatomic, readwrite) BOOL       isEdited;
@property(nonatomic, readwrite) BOOL       isArtworkEdited;

@property(nonatomic, readwrite, copy) NSString *presetName;

@property(nonatomic, readwrite, retain) NSMutableArray<MP42Image *> *artworks;

@end

NS_ASSUME_NONNULL_END
