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

// Common Metadata keys
extern NSString *const MP42MetadataKeyName;
extern NSString *const MP42MetadataKeyTrackSubTitle;

extern NSString *const MP42MetadataKeyAlbum;
extern NSString *const MP42MetadataKeyAlbumArtist;
extern NSString *const MP42MetadataKeyArtist;

extern NSString *const MP42MetadataKeyGrouping;
extern NSString *const MP42MetadataKeyUserComment;
extern NSString *const MP42MetadataKeyUserGenre;
extern NSString *const MP42MetadataKeyReleaseDate;

extern NSString *const MP42MetadataKeyTrackNumber;
extern NSString *const MP42MetadataKeyDiscNumber;
extern NSString *const MP42MetadataKeyBeatsPerMin;

extern NSString *const MP42MetadataKeyKeywords;
extern NSString *const MP42MetadataKeyCategory;
extern NSString *const MP42MetadataKeyCredits;
extern NSString *const MP42MetadataKeyThanks;
extern NSString *const MP42MetadataKeyCopyright;

extern NSString *const MP42MetadataKeyDescription;
extern NSString *const MP42MetadataKeyLongDescription;
extern NSString *const MP42MetadataKeySeriesDescription;
extern NSString *const MP42MetadataKeySongDescription;

extern NSString *const MP42MetadataKeyRating;
extern NSString *const MP42MetadataKeyRatingAnnotation;
extern NSString *const MP42MetadataKeyContentRating;

// Encoding Metadata keys
extern NSString *const MP42MetadataKeyEncodedBy;
extern NSString *const MP42MetadataKeyEncodingTool;

// TODO
extern NSString *const MP42MetadataKeyCoverArt;
extern NSString *const MP42MetadataKeyMediaKind;
extern NSString *const MP42MetadataKeyGapless;
extern NSString *const MP42MetadataKeyHDVideo;
extern NSString *const MP42MetadataKeyiTunesU;

// Movie and TV Show Specific keys
extern NSString *const MP42MetadataKeyStudio;
extern NSString *const MP42MetadataKeyCast;
extern NSString *const MP42MetadataKeyDirector;
extern NSString *const MP42MetadataKeyCodirector;
extern NSString *const MP42MetadataKeyProducer;
extern NSString *const MP42MetadataKeyExecProducer;
extern NSString *const MP42MetadataKeyScreenwriters;

// TV Show Specific Metadata keys
extern NSString *const MP42MetadataKeyTVShow;
extern NSString *const MP42MetadataKeyTVEpisodeNumber;
extern NSString *const MP42MetadataKeyTVNetwork;
extern NSString *const MP42MetadataKeyTVEpisodeID;
extern NSString *const MP42MetadataKeyTVSeason;

// Songs Specific Metadata Keys
extern NSString *const MP42MetadataKeyArtDirector;
extern NSString *const MP42MetadataKeyComposer;
extern NSString *const MP42MetadataKeyArranger;
extern NSString *const MP42MetadataKeyAuthor;
extern NSString *const MP42MetadataKeyLyrics;
extern NSString *const MP42MetadataKeyAcknowledgement;
extern NSString *const MP42MetadataKeyConductor;
extern NSString *const MP42MetadataKeyLinerNotes;
extern NSString *const MP42MetadataKeyRecordCompany;
extern NSString *const MP42MetadataKeyOriginalArtist;
extern NSString *const MP42MetadataKeyPhonogramRights;
extern NSString *const MP42MetadataKeySongProducer;
extern NSString *const MP42MetadataKeyPerformer;
extern NSString *const MP42MetadataKeyPublisher;
extern NSString *const MP42MetadataKeySoundEngineer;
extern NSString *const MP42MetadataKeySoloist;
extern NSString *const MP42MetadataKeyDiscCompilation;

// Classic Music Specific Metadata Keys
extern NSString *const MP42MetadataKeyWorkName;
extern NSString *const MP42MetadataKeyMovementName;
extern NSString *const MP42MetadataKeyMovementNumber;
extern NSString *const MP42MetadataKeyMovementCount;
extern NSString *const MP42MetadataKeyShowWorkAndMovement;

// iTunes Store Metadata keys
extern NSString *const MP42MetadataKeyXID;
extern NSString *const MP42MetadataKeyArtistID;
extern NSString *const MP42MetadataKeyComposerID;
extern NSString *const MP42MetadataKeyContentID;
extern NSString *const MP42MetadataKeyGenreID;
extern NSString *const MP42MetadataKeyPlaylistID;
extern NSString *const MP42MetadataKeyAppleID;
extern NSString *const MP42MetadataKeyAccountKind;
extern NSString *const MP42MetadataKeyAccountCountry;
extern NSString *const MP42MetadataKeyPurchasedDate;
extern NSString *const MP42MetadataKeyOnlineExtras;

// Sort Metadata Keys
extern NSString *const MP42MetadataKeySortName;
extern NSString *const MP42MetadataKeySortArtist;
extern NSString *const MP42MetadataKeySortAlbumArtist;
extern NSString *const MP42MetadataKeySortAlbum;
extern NSString *const MP42MetadataKeySortComposer;
extern NSString *const MP42MetadataKeySortTVShow;

@interface MP42Metadata : NSObject <NSCoding, NSCopying>

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
+ (NSArray<NSString *> *) writableMetadata;

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
