//
//  MP42Metadata.m
//  Subler
//
//  Created by Damiano Galassi on 06/02/09.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42Metadata.h"
#import "MP42PrivateUtilities.h"
#import "MP42XMLReader.h"
#import "MP42Image.h"

#import "NSString+MP42Additions.h"
#import "MP42MetadataUtilities.h"

@interface MP42Metadata ()

@property (nonatomic, readonly MP42_DIRECT) NSMutableArray<MP42MetadataItem *> *itemsArray;
@property (nonatomic, readonly MP42_DIRECT) NSMutableDictionary<NSString *, MP42MetadataItem *> *itemsMap;

@property (nonatomic, readwrite, getter=isArtworkEdited) BOOL artworkEdited;
@property (nonatomic, readwrite, getter=isEdited) BOOL edited;

@end

@implementation MP42Metadata

- (instancetype)init
{
    self = [super init];
	if (self)
	{
        _itemsArray = [[NSMutableArray alloc] init];
        _itemsMap = [[NSMutableDictionary alloc] init];
        _edited = NO;
        _artworkEdited = NO;
	}

    return self;
}

- (instancetype)initWithFileHandle:(MP4FileHandle)fileHandle
{
    self = [self init];
    if (self) {
        [self readMetaDataFromFileHandle:fileHandle];
	}

    return self;
}

- (nullable instancetype)initWithURL:(NSURL *)URL
{
    self = [self init];
    if (self) {
        MP42XMLReader *xmlReader = [[MP42XMLReader alloc] initWithURL:URL error:NULL];
        if (xmlReader) {
            [self mergeMetadata:[xmlReader mMetadata]];
        } else {
            return nil;
        }
	}
    
    return self;
}

#pragma mark - Supported metadata

+ (NSArray<NSString *> *)availableMetadata
{
    return @[
            MP42MetadataKeyName,
            MP42MetadataKeyTrackSubTitle,
            MP42MetadataKeyArtist,
            MP42MetadataKeyAlbumArtist,
            MP42MetadataKeyAlbum,
            MP42MetadataKeyGrouping,
            MP42MetadataKeyMediaKind,
            MP42MetadataKeyHDVideo,
            MP42MetadataKeyGapless,
            MP42MetadataKeyPodcast,
			MP42MetadataKeyUserComment,
            MP42MetadataKeyUserGenre,
            MP42MetadataKeyReleaseDate,
            MP42MetadataKeyTrackNumber,
            MP42MetadataKeyDiscNumber,
            MP42MetadataKeyBeatsPerMin,
            MP42MetadataKeyTVShow,
            MP42MetadataKeyTVEpisodeNumber,
			MP42MetadataKeyTVNetwork,
            MP42MetadataKeyTVEpisodeID,
            MP42MetadataKeyTVSeason,
            MP42MetadataKeyDescription,
            MP42MetadataKeyLongDescription,
            MP42MetadataKeySeriesDescription,
            MP42MetadataKeyRating,
            MP42MetadataKeyRatingAnnotation,
            MP42MetadataKeyContentRating,
            MP42MetadataKeyStudio,
            MP42MetadataKeyCast,
            MP42MetadataKeyDirector,
            MP42MetadataKeyCodirector,
            MP42MetadataKeyProducer,
            MP42MetadataKeyExecProducer,
            MP42MetadataKeyScreenwriters,
            MP42MetadataKeyCopyright,
            MP42MetadataKeyEncodingTool,
            MP42MetadataKeyEncodedBy,
            MP42MetadataKeyKeywords,
            MP42MetadataKeyCategory,
            MP42MetadataKeyContentID,
            MP42MetadataKeyArtistID,
            MP42MetadataKeyPlaylistID,
            MP42MetadataKeyGenreID,
            MP42MetadataKeyComposerID,
            MP42MetadataKeyXID,
            MP42MetadataKeyAppleID,
            MP42MetadataKeyAccountKind,
            MP42MetadataKeyAccountCountry,
            MP42MetadataKeyPurchasedDate,
            MP42MetadataKeyOnlineExtras,
            MP42MetadataKeySongDescription,
            MP42MetadataKeyArtDirector,
            MP42MetadataKeyComposer,
            MP42MetadataKeyArranger,
            MP42MetadataKeyAuthor,
            MP42MetadataKeyLyrics,
            MP42MetadataKeyAcknowledgement,
            MP42MetadataKeyConductor,
            MP42MetadataKeyLinerNotes,
            MP42MetadataKeyRecordCompany,
            MP42MetadataKeyOriginalArtist,
            MP42MetadataKeyPhonogramRights,
            MP42MetadataKeySongProducer,
            MP42MetadataKeyPerformer,
            MP42MetadataKeyPublisher,
            MP42MetadataKeySoundEngineer,
            MP42MetadataKeySoloist,
            MP42MetadataKeyDiscCompilation,
            MP42MetadataKeyCredits,
            MP42MetadataKeyThanks,
            MP42MetadataKeyWorkName,
            MP42MetadataKeyMovementName,
            MP42MetadataKeyMovementNumber,
            MP42MetadataKeyMovementCount,
            MP42MetadataKeyShowWorkAndMovement,
            MP42MetadataKeySortName,
            MP42MetadataKeySortArtist,
            MP42MetadataKeySortAlbumArtist,
            MP42MetadataKeySortAlbum,
            MP42MetadataKeySortComposer,
            MP42MetadataKeySortTVShow,
            MP42MetadataKeyUnofficialSubtitle,
            MP42MetadataKeyUnofficialLanguage,
            MP42MetadataKeyUnofficialASIN,
            MP42MetadataKeyUnofficialAbridged];
}

+ (NSArray<NSString *> *)writableMetadata
{
    return @[
            MP42MetadataKeyName,
            MP42MetadataKeyTrackSubTitle,
            MP42MetadataKeyArtist,
            MP42MetadataKeyAlbumArtist,
            MP42MetadataKeyAlbum,
            MP42MetadataKeyGrouping,
            MP42MetadataKeyMediaKind,
            MP42MetadataKeyHDVideo,
            MP42MetadataKeyGapless,
            MP42MetadataKeyPodcast,
            MP42MetadataKeyComposer,
			MP42MetadataKeyUserComment,
            MP42MetadataKeyUserGenre,
            MP42MetadataKeyReleaseDate,
            MP42MetadataKeyTrackNumber,
            MP42MetadataKeyDiscNumber,
            MP42MetadataKeyBeatsPerMin,
            MP42MetadataKeyTVShow,
            MP42MetadataKeyTVEpisodeNumber,
			MP42MetadataKeyTVNetwork,
            MP42MetadataKeyTVEpisodeID,
            MP42MetadataKeyTVSeason,
            MP42MetadataKeySongDescription,
            MP42MetadataKeyDescription,
            MP42MetadataKeyLongDescription,
            MP42MetadataKeySeriesDescription,
            MP42MetadataKeyRating,
            MP42MetadataKeyRatingAnnotation,
            MP42MetadataKeyContentRating,
            MP42MetadataKeyStudio,
            MP42MetadataKeyCast,
            MP42MetadataKeyDirector,
            MP42MetadataKeyCodirector,
            MP42MetadataKeyProducer,
            MP42MetadataKeyExecProducer,
            MP42MetadataKeyScreenwriters,
            MP42MetadataKeyLyrics,
            MP42MetadataKeyCopyright,
            MP42MetadataKeyEncodingTool,
            MP42MetadataKeyEncodedBy,
            MP42MetadataKeyKeywords,
            MP42MetadataKeyCategory,
            MP42MetadataKeyContentID,
            MP42MetadataKeyArtistID,
            MP42MetadataKeyPlaylistID,
            MP42MetadataKeyGenreID,
            MP42MetadataKeyComposerID,
            MP42MetadataKeyXID,
            MP42MetadataKeyAppleID,
            MP42MetadataKeyAccountKind,
            MP42MetadataKeyAccountCountry,
            MP42MetadataKeyPurchasedDate,
            MP42MetadataKeyOnlineExtras,
            MP42MetadataKeyArtDirector,
            MP42MetadataKeyArranger,
            MP42MetadataKeyAuthor,
            MP42MetadataKeyAcknowledgement,
            MP42MetadataKeyConductor,
            MP42MetadataKeyLinerNotes,
            MP42MetadataKeyRecordCompany,
            MP42MetadataKeyOriginalArtist,
            MP42MetadataKeyPhonogramRights,
            MP42MetadataKeySongProducer,
            MP42MetadataKeyPerformer,
            MP42MetadataKeyPublisher,
            MP42MetadataKeySoundEngineer,
            MP42MetadataKeySoloist,
            MP42MetadataKeyDiscCompilation,
            MP42MetadataKeyCredits,
            MP42MetadataKeyThanks,
            MP42MetadataKeyWorkName,
            MP42MetadataKeyMovementName,
            MP42MetadataKeyMovementNumber,
            MP42MetadataKeyMovementCount,
            MP42MetadataKeyShowWorkAndMovement,
            MP42MetadataKeySortName,
            MP42MetadataKeySortArtist,
            MP42MetadataKeySortAlbumArtist,
            MP42MetadataKeySortAlbum,
            MP42MetadataKeySortComposer,
            MP42MetadataKeySortTVShow,
            MP42MetadataKeyUnofficialSubtitle,
            MP42MetadataKeyUnofficialLanguage,
            MP42MetadataKeyUnofficialASIN,
            MP42MetadataKeyUnofficialAbridged
    ];
}

#pragma mark - Public methods

- (NSArray<MP42MetadataItem *> *)metadataItemsFilteredByIdentifier:(NSString *)identifier
{
    NSMutableArray<MP42MetadataItem *> *result = [NSMutableArray array];

    for (MP42MetadataItem *item in self.itemsArray) {
        if ([item.identifier isEqualToString:identifier]) {
            [result addObject:item];
        }
    }

    return result;
}

- (NSArray<MP42MetadataItem *> *)metadataItemsFilteredByIdentifiers:(NSArray<NSString *> *)identifiers
{
    NSMutableArray<MP42MetadataItem *> *result = [NSMutableArray array];
    NSSet *identifiersSet = [NSSet setWithArray:identifiers];

    for (MP42MetadataItem *item in self.itemsArray) {
        if ([identifiersSet containsObject:item.identifier]) {
            [result addObject:item];
        }
    }

    return result;
}

- (NSArray<MP42MetadataItem *> *)metadataItemsFilteredByDataType:(MP42MetadataItemDataType)dataTypeMask
{
    NSMutableArray<MP42MetadataItem *> *result = [NSMutableArray array];

    for (MP42MetadataItem *item in self.itemsArray) {
        if (item.dataType & dataTypeMask) {
            [result addObject:item];
        }
    }

    return result;
}

- (void)addMetadataItem:(MP42MetadataItem *)item
{
    // Only one metadata item per identifier for now,
    // as we don't support multiple languages yet,
    // Allow multiple MP42MetadataKeyCoverArt items.
    if ([item.identifier isEqualToString:MP42MetadataKeyCoverArt]) {
        self.artworkEdited = YES;
    } else {
        MP42MetadataItem *existingItem = self.itemsMap[item.identifier];
        if (existingItem) {
            [self.itemsArray removeObject:existingItem];
        }
    }
    [self.itemsArray addObject:item];
    [self.itemsMap setObject:item forKey:item.identifier];
    self.edited = YES;
}

- (void)addMetadataItems:(NSArray<MP42MetadataItem *> *)items
{
    for (MP42MetadataItem *item in items) {
        [self addMetadataItem:item];
    }
}

- (void)removeMetadataItem:(MP42MetadataItem *)item
{
    [self.itemsArray removeObject:item];
    [self.itemsMap removeObjectForKey:item.identifier];

    if ([item.identifier isEqualToString:MP42MetadataKeyCoverArt]) {
        self.artworkEdited = YES;
    }
    else {
        self.edited = YES;
    }
}

- (void)removeMetadataItems:(NSArray<MP42MetadataItem *> *)items
{
    for (MP42MetadataItem *item in items) {
        [self removeMetadataItem:item];
    }
}

- (NSArray<MP42MetadataItem *> *)items
{
    return [self.itemsArray copy];
}

#pragma mark - Array conversion

/**
 *  Converts an array of NSDictionary to a single string
 *  with the components separated by ", ".
 *
 *  @param array the array of strings.
 *
 *  @return a concatenated string.
 */
- (NSMutableArray<NSString *> *)stringArrayFromDictionaryArray:(NSArray<NSDictionary *> *)array key:(id)key {
    NSMutableArray *result = [NSMutableArray array];

    if ([array isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in array) {
            if ([dict isKindOfClass:[NSDictionary class]]) {
                [result addObject:dict[key]];
            }
        }
    }
    else if ([array isKindOfClass:[NSString class]]) {
        NSString *name = (NSString *)array;
        [result addObject:name];
    }

    return [result copy];
}

/**
 *  Splits a string into components separated by ",".
 *
 *  @param string to separate
 *
 *  @return an array of separated components.
 */
- (NSArray<NSDictionary *> *)dictArrayFromStringArray:(NSArray<NSString *> *)array key:(id)key {
    NSMutableArray *arrayElements = [NSMutableArray array];

    for (NSString *name in array) {
        [arrayElements addObject: @{ key: name}];
    }

    return arrayElements;
}

#pragma mark - Metadata conversion helpers

/**
 *  Trys to create a NSString using various encoding.
 *
 *  @param cString the input string
 *
 *  @return a instances of NSString.
 */
- (NSString *)stringFromMetadata:(const char *)cString {
    NSString *string = nil;

    if ((string = [NSString stringWithCString:cString encoding: NSUTF8StringEncoding])) {
        return string;
    }

    if ((string = [NSString stringWithCString:cString encoding: NSASCIIStringEncoding])) {
        return string;
    }

    if ((string = [NSString stringWithCString:cString encoding: NSUTF16StringEncoding])) {
        return string;
    }

    return @"";
}

#pragma mark - Mutators

- (void)mergeMetadata:(MP42Metadata *)metadata {
    NSArray<MP42MetadataItem *> *coverArts = [metadata metadataItemsFilteredByIdentifier:MP42MetadataKeyCoverArt];

    // Remove existings cover arts only if new one is available
    if (coverArts.count) {
        for (MP42MetadataItem *item in [self metadataItemsFilteredByIdentifier:MP42MetadataKeyCoverArt]) {
            [self removeMetadataItem:item];
        }
    }

    for (MP42MetadataItem *item in metadata.items) {
        [self addMetadataItem:[item copy]];
    }

    self.edited = YES;
    self.artworkEdited = YES;
}

#pragma mark - MP42Foundation/mp4v2 read/write mapping

- (void)addMetadataItemWithUTF8String:(const char *)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    NSString *string = [NSString stringWithCString:value encoding:NSUTF8StringEncoding];

    if (!string) {
        string = [NSString stringWithCString:value encoding:NSASCIIStringEncoding];
    }
    if (!string) {
        string = [NSString stringWithCString:value encoding:NSUTF16StringEncoding];
    }
    if (!string) {
        string = @"";
    }

    [self addMetadataItemWithString:string identifier:identifier];
}

- (void)addMetadataItemWithDateString:(const char *)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    NSString *string = [NSString stringWithCString:value encoding:NSUTF8StringEncoding];

    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:string
                                                                 dataType:MP42MetadataItemDataTypeUnspecified
                                                      extendedLanguageTag:nil];
    [self.itemsArray addObject:item];
    [self.itemsMap setObject:item forKey:identifier];
}

- (void)addMetadataItemWithString:(NSString *)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeString
                                                      extendedLanguageTag:nil];
    [self.itemsArray addObject:item];
    [self.itemsMap setObject:item forKey:identifier];
}

- (void)addMetadataItemWithStringArray:(NSArray<NSString *> *)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeStringArray
                                                      extendedLanguageTag:nil];
    [self.itemsArray addObject:item];
    [self.itemsMap setObject:item forKey:identifier];
}

- (void)addMetadataItemWithBool:(BOOL)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:@(value)
                                                                 dataType:MP42MetadataItemDataTypeBool
                                                      extendedLanguageTag:nil];
    [self.itemsArray addObject:item];
    [self.itemsMap setObject:item forKey:identifier];
}

- (void)addMetadataItemWithInteger:(NSInteger)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:@(value)
                                                                 dataType:MP42MetadataItemDataTypeInteger
                                                      extendedLanguageTag:nil];
    [self.itemsArray addObject:item];
    [self.itemsMap setObject:item forKey:identifier];
}
- (void)addMetadataItemWithIntegerArray:(NSArray<NSNumber *> *)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeIntegerArray
                                                      extendedLanguageTag:nil];
    [self.itemsArray addObject:item];
    [self.itemsMap setObject:item forKey:identifier];
}

- (void)addMetadataItemWithImage:(MP42Image *)value identifier:(NSString *)identifier MP42_OBJC_DIRECT
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeImage
                                                      extendedLanguageTag:nil];
    [self.itemsArray addObject:item];
}

- (void)readMetaDataFromFileHandle:(MP4FileHandle)sourceHandle MP42_OBJC_DIRECT
{
    const MP4Tags *tags = MP4TagsAlloc();
    MP4TagsFetch (tags, sourceHandle);

    if (tags->name) {
        [self addMetadataItemWithUTF8String:tags->name identifier:MP42MetadataKeyName];
    }
    if (tags->artist) {
        [self addMetadataItemWithUTF8String:tags->artist identifier:MP42MetadataKeyArtist];
    }
    if (tags->albumArtist) {
        [self addMetadataItemWithUTF8String:tags->albumArtist identifier:MP42MetadataKeyAlbumArtist];
    }
    if (tags->album) {
        [self addMetadataItemWithUTF8String:tags->album identifier:MP42MetadataKeyAlbum];
    }
    if (tags->grouping) {
        [self addMetadataItemWithUTF8String:tags->grouping identifier:MP42MetadataKeyGrouping];
    }
    if (tags->composer) {
        [self addMetadataItemWithUTF8String:tags->composer identifier:MP42MetadataKeyComposer];
    }
    if (tags->comments) {
        [self addMetadataItemWithUTF8String:tags->comments identifier:MP42MetadataKeyUserComment];
    }
    if (tags->genre) {
        [self addMetadataItemWithUTF8String:tags->genre identifier:MP42MetadataKeyUserGenre];
    }
    if (tags->genreType && !tags->genre) {
        NSString *genre = genreFromIndex(*tags->genreType);
        if (genre) {
            [self addMetadataItemWithString:genre identifier:MP42MetadataKeyUserGenre];
        }
    }
    if (tags->releaseDate) {
        [self addMetadataItemWithDateString:tags->releaseDate identifier:MP42MetadataKeyReleaseDate];
    }
    if (tags->track) {
        [self addMetadataItemWithIntegerArray:@[@(tags->track->index), @(tags->track->total)] identifier:MP42MetadataKeyTrackNumber];
    }
    if (tags->disk) {
        [self addMetadataItemWithIntegerArray:@[@(tags->disk->index), @(tags->disk->total)] identifier:MP42MetadataKeyDiscNumber];
    }
    if (tags->tempo) {
        [self addMetadataItemWithInteger:*tags->tempo identifier:MP42MetadataKeyBeatsPerMin];
    }
    if (tags->trackSubTitle) {
        [self addMetadataItemWithUTF8String:tags->trackSubTitle identifier:MP42MetadataKeyTrackSubTitle];
    }
    if (tags->songDescription) {
        [self addMetadataItemWithUTF8String:tags->songDescription identifier:MP42MetadataKeySongDescription];
    }
    if (tags->director) {
        [self addMetadataItemWithUTF8String:tags->director identifier:MP42MetadataKeyDirector];
    }
    if (tags->artDirector) {
        [self addMetadataItemWithUTF8String:tags->artDirector identifier:MP42MetadataKeyArtDirector];
    }
    if (tags->arranger) {
        [self addMetadataItemWithUTF8String:tags->arranger identifier:MP42MetadataKeyArranger];
    }
    if (tags->lyricist) {
        [self addMetadataItemWithUTF8String:tags->lyricist identifier:MP42MetadataKeyAuthor];
    }
    if (tags->acknowledgement) {
        [self addMetadataItemWithUTF8String:tags->acknowledgement identifier:MP42MetadataKeyAcknowledgement];
    }
    if (tags->conductor) {
        [self addMetadataItemWithUTF8String:tags->conductor identifier:MP42MetadataKeyConductor];
    }
    if (tags->workName) {
        [self addMetadataItemWithUTF8String:tags->workName identifier:MP42MetadataKeyWorkName];
    }
    if (tags->movementName) {
        [self addMetadataItemWithUTF8String:tags->movementName identifier:MP42MetadataKeyMovementName];
    }
    if (tags->movementCount) {
        [self addMetadataItemWithInteger:*tags->movementCount identifier:MP42MetadataKeyMovementCount];
    }
    if (tags->movementNumber) {
        [self addMetadataItemWithInteger:*tags->movementNumber identifier:MP42MetadataKeyMovementNumber];
    }
    if (tags->showWorkAndMovement) {
        [self addMetadataItemWithBool:*tags->showWorkAndMovement identifier:MP42MetadataKeyShowWorkAndMovement];
    }
    if (tags->linearNotes) {
        [self addMetadataItemWithUTF8String:tags->linearNotes identifier:MP42MetadataKeyLinerNotes];
    }
    if (tags->recordCompany) {
        [self addMetadataItemWithUTF8String:tags->recordCompany identifier:MP42MetadataKeyRecordCompany];
    }
    if (tags->originalArtist) {
        [self addMetadataItemWithUTF8String:tags->originalArtist identifier:MP42MetadataKeyOriginalArtist];
    }
    if (tags->phonogramRights) {
        [self addMetadataItemWithUTF8String:tags->phonogramRights identifier:MP42MetadataKeyPhonogramRights];
    }
    if (tags->producer) {
        [self addMetadataItemWithUTF8String:tags->producer identifier:MP42MetadataKeySongProducer];
    }
    if (tags->performer) {
        [self addMetadataItemWithUTF8String:tags->performer identifier:MP42MetadataKeyPerformer];
    }
    if (tags->publisher) {
        [self addMetadataItemWithUTF8String:tags->publisher identifier:MP42MetadataKeyPublisher];
    }
    if (tags->soundEngineer) {
        [self addMetadataItemWithUTF8String:tags->soundEngineer identifier:MP42MetadataKeySoundEngineer];
    }
    if (tags->soloist) {
        [self addMetadataItemWithUTF8String:tags->soloist identifier:MP42MetadataKeySoloist];
    }
    if (tags->compilation) {
        [self addMetadataItemWithBool:*tags->compilation identifier:MP42MetadataKeyDiscCompilation];
    }
    if (tags->credits) {
        [self addMetadataItemWithUTF8String:tags->credits identifier:MP42MetadataKeyCredits];
    }
    if (tags->thanks) {
        [self addMetadataItemWithUTF8String:tags->thanks identifier:MP42MetadataKeyThanks];
    }
    if (tags->onlineExtras) {
        [self addMetadataItemWithUTF8String:tags->onlineExtras identifier:MP42MetadataKeyOnlineExtras];
    }
    if (tags->executiveProducer) {
        [self addMetadataItemWithUTF8String:tags->executiveProducer identifier:MP42MetadataKeyExecProducer];
    }
    if (tags->tvShow) {
        [self addMetadataItemWithUTF8String:tags->tvShow identifier:MP42MetadataKeyTVShow];
    }
    if (tags->tvEpisodeID) {
        [self addMetadataItemWithUTF8String:tags->tvEpisodeID identifier:MP42MetadataKeyTVEpisodeID];
    }
    if (tags->tvSeason) {
        [self addMetadataItemWithInteger:*tags->tvSeason identifier:MP42MetadataKeyTVSeason];
    }
    if (tags->tvEpisode) {
        [self addMetadataItemWithInteger:*tags->tvEpisode identifier:MP42MetadataKeyTVEpisodeNumber];
    }
    if (tags->tvNetwork) {
        [self addMetadataItemWithUTF8String:tags->tvNetwork identifier:MP42MetadataKeyTVNetwork];
    }
    if (tags->description) {
        [self addMetadataItemWithUTF8String:tags->description identifier:MP42MetadataKeyDescription];
    }
    if (tags->longDescription) {
        [self addMetadataItemWithUTF8String:tags->longDescription identifier:MP42MetadataKeyLongDescription];
    }
    if (tags->seriesDescription) {
        [self addMetadataItemWithUTF8String:tags->seriesDescription identifier:MP42MetadataKeySeriesDescription];
    }
    if (tags->lyrics) {
        [self addMetadataItemWithUTF8String:tags->lyrics identifier:MP42MetadataKeyLyrics];
    }
    if (tags->copyright) {
        [self addMetadataItemWithUTF8String:tags->copyright identifier:MP42MetadataKeyCopyright];
    }
    if (tags->encodingTool) {
        [self addMetadataItemWithUTF8String:tags->encodingTool identifier:MP42MetadataKeyEncodingTool];
    }
    if (tags->encodedBy) {
        [self addMetadataItemWithUTF8String:tags->encodedBy identifier:MP42MetadataKeyEncodedBy];
    }
    if (tags->hdVideo) {
        [self addMetadataItemWithInteger:*tags->hdVideo identifier:MP42MetadataKeyHDVideo];
    }
    if (tags->mediaType) {
        [self addMetadataItemWithInteger:*tags->mediaType identifier:MP42MetadataKeyMediaKind];
    }
    if (tags->contentRating) {
        [self addMetadataItemWithInteger:*tags->contentRating identifier:MP42MetadataKeyContentRating];
    }
    if (tags->gapless) {
        [self addMetadataItemWithBool:*tags->gapless identifier:MP42MetadataKeyGapless];
    }
    if (tags->purchaseDate) {
        [self addMetadataItemWithUTF8String:tags->purchaseDate identifier:MP42MetadataKeyPurchasedDate];
    }
    if (tags->iTunesAccount) {
        [self addMetadataItemWithUTF8String:tags->iTunesAccount identifier:MP42MetadataKeyAppleID];
    }
    if (tags->iTunesAccountType) {
        [self addMetadataItemWithInteger:*tags->iTunesAccountType identifier:MP42MetadataKeyAccountKind];
    }
    if (tags->iTunesCountry) {
        [self addMetadataItemWithInteger:*tags->iTunesCountry identifier:MP42MetadataKeyAccountCountry];
    }
    if (tags->contentID) {
        [self addMetadataItemWithInteger:*tags->contentID identifier:MP42MetadataKeyContentID];
    }
    if (tags->artistID) {
        [self addMetadataItemWithInteger:*tags->artistID identifier:MP42MetadataKeyArtistID];
    }
    if (tags->playlistID) {
        [self addMetadataItemWithInteger:*tags->playlistID identifier:MP42MetadataKeyPlaylistID];
    }
    if (tags->genreID) {
        [self addMetadataItemWithInteger:*tags->genreID identifier:MP42MetadataKeyGenreID];
    }
    if (tags->composerID) {
        [self addMetadataItemWithInteger:*tags->composerID identifier:MP42MetadataKeyComposerID];
    }
    if (tags->xid) {
        [self addMetadataItemWithUTF8String:tags->xid identifier:MP42MetadataKeyXID];
    }
    if (tags->sortName) {
        [self addMetadataItemWithUTF8String:tags->sortName identifier:MP42MetadataKeySortName];
    }
    if (tags->sortArtist) {
        [self addMetadataItemWithUTF8String:tags->sortArtist identifier:MP42MetadataKeySortArtist];
    }
    if (tags->sortAlbumArtist) {
        [self addMetadataItemWithUTF8String:tags->sortAlbumArtist identifier:MP42MetadataKeySortAlbumArtist];
    }
    if (tags->sortAlbum) {
        [self addMetadataItemWithUTF8String:tags->sortAlbum identifier:MP42MetadataKeySortAlbum];
    }
    if (tags->sortComposer) {
        [self addMetadataItemWithUTF8String:tags->sortComposer identifier:MP42MetadataKeySortComposer];
    }
    if (tags->sortTVShow) {
        [self addMetadataItemWithUTF8String:tags->sortTVShow identifier:MP42MetadataKeySortTVShow];
    }
    if (tags->podcast) {
        [self addMetadataItemWithBool:*tags->podcast identifier:MP42MetadataKeyPodcast];
    }
    if (tags->keywords) {
        [self addMetadataItemWithUTF8String:tags->keywords identifier:MP42MetadataKeyKeywords];
    }
    if (tags->category) {
        [self addMetadataItemWithUTF8String:tags->category identifier:MP42MetadataKeyCategory];
    }
    if (tags->artwork) {
        for (uint32_t i = 0; i < tags->artworkCount; i++) {
            MP42Image *artwork = [[MP42Image alloc] initWithBytes:tags->artwork[i].data length:tags->artwork[i].size type:(MP42TagArtworkType)tags->artwork[i].type];
            [self addMetadataItemWithImage:artwork identifier:MP42MetadataKeyCoverArt];
        }
    }

    MP4TagsFree(tags);

    // read the remaining iTMF items
    MP4ItmfItemList *list = MP4ItmfGetItemsByMeaning(sourceHandle, "com.apple.iTunes", "iTunEXTC");
    if (list) {
        for (uint32_t i = 0; i < list->size; i++) {
            MP4ItmfItem *item = &list->elements[i];

            for (uint32_t j = 0; j < item->dataList.size; j++) {
                MP4ItmfData *data = &item->dataList.elements[j];

                NSString *ratingString = [[NSString alloc] initWithBytes:data->value length: data->valueSize encoding:NSUTF8StringEncoding];

                NSString *splitElements  = @"\\|";
                NSArray *ratingItems = [ratingString MP42_componentsSeparatedByRegex:splitElements];

                if (ratingItems.count > 2) {
                    [self addMetadataItemWithString:[NSString stringWithFormat:@"%@|%@|%@|", ratingItems[0], ratingItems[1], ratingItems[2]]
                                         identifier:MP42MetadataKeyRating];
                }

                if (ratingItems.count >= 4) {
                    [self addMetadataItemWithString:ratingItems[3] identifier:MP42MetadataKeyRatingAnnotation];
                }
            }
        }

        MP4ItmfItemListFree(list);
    }

    list = MP4ItmfGetItemsByMeaning(sourceHandle, "com.apple.iTunes", "iTunMOVI");
    if (list) {
        for (uint32_t i = 0; i < list->size; i++) {
            MP4ItmfItem *item = &list->elements[i];
            for (uint32_t j = 0; j < item->dataList.size; j++) {
                MP4ItmfData *data = &item->dataList.elements[j];
                NSData *xmlData = [NSData dataWithBytes:data->value length:data->valueSize];
                NSDictionary *dma = (NSDictionary *)[NSPropertyListSerialization propertyListWithData:xmlData
                                                                                              options:NSPropertyListImmutable
                                                                                               format:nil error:NULL];

                id tag = nil;

                if ([tag = [self stringArrayFromDictionaryArray:dma[@"cast"] key:@"name"] count]) {
                    [self addMetadataItemWithStringArray:tag identifier:MP42MetadataKeyCast];
                }

                if ([tag = [self stringArrayFromDictionaryArray:dma[@"directors"] key:@"name"] count]) {
                    // Replace the @dir tag
                    NSArray<MP42MetadataItem *> *items = [self metadataItemsFilteredByIdentifier:MP42MetadataKeyDirector];
                    if (items) {
                        [self removeMetadataItems:items];
                    }
                    [self addMetadataItemWithStringArray:tag identifier:MP42MetadataKeyDirector];
                }

                if ([tag = [self stringArrayFromDictionaryArray:dma[@"codirectors"] key:@"name"] count]) {
                    [self addMetadataItemWithStringArray:tag identifier:MP42MetadataKeyCodirector];
                }

                if ([tag = [self stringArrayFromDictionaryArray:dma[@"producers"] key:@"name"] count]) {
                    [self addMetadataItemWithStringArray:tag identifier:MP42MetadataKeyProducer];
                }

                if ([tag = [self stringArrayFromDictionaryArray:dma[@"screenwriters"] key:@"name"] count]) {
                    [self addMetadataItemWithStringArray:tag identifier:MP42MetadataKeyScreenwriters];
                }

                if ((tag = dma[@"studio"]) != nil && [tag isKindOfClass:[NSString class]]) {
                    NSString *studio = tag;
                    if (studio.length) {
                        [self addMetadataItemWithString:tag identifier:MP42MetadataKeyStudio];
                    }
                }
            }
        }
        MP4ItmfItemListFree(list);
    }

    list = MP4ItmfGetItemsByMeaning(sourceHandle, "com.apple.iTunes", "SUBTITLE");
    if (list) {
        for (uint32_t i = 0; i < list->size; i++) {
            MP4ItmfItem *item = &list->elements[i];

            for (uint32_t j = 0; j < item->dataList.size; j++) {
                MP4ItmfData *data = &item->dataList.elements[j];
                NSString *tag = [[NSString alloc] initWithBytes:data->value length: data->valueSize encoding:NSUTF8StringEncoding];

                if (tag.length) {
                    [self addMetadataItemWithString:tag identifier:MP42MetadataKeyUnofficialSubtitle];
                }
            }
        }
        MP4ItmfItemListFree(list);
    }

    list = MP4ItmfGetItemsByMeaning(sourceHandle, "com.apple.iTunes", "LANGUAGE");
    if (list) {
        for (uint32_t i = 0; i < list->size; i++) {
            MP4ItmfItem *item = &list->elements[i];

            for (uint32_t j = 0; j < item->dataList.size; j++) {
                MP4ItmfData *data = &item->dataList.elements[j];
                NSString *tag = [[NSString alloc] initWithBytes:data->value length: data->valueSize encoding:NSUTF8StringEncoding];

                if (tag.length) {
                    [self addMetadataItemWithString:tag identifier:MP42MetadataKeyUnofficialLanguage];
                }
            }
        }
        MP4ItmfItemListFree(list);
    }

    list = MP4ItmfGetItemsByMeaning(sourceHandle, "com.apple.iTunes", "ASIN");
    if (list) {
        for (uint32_t i = 0; i < list->size; i++) {
            MP4ItmfItem *item = &list->elements[i];

            for (uint32_t j = 0; j < item->dataList.size; j++) {
                MP4ItmfData *data = &item->dataList.elements[j];
                NSString *tag = [[NSString alloc] initWithBytes:data->value length: data->valueSize encoding:NSUTF8StringEncoding];

                if (tag.length) {
                    [self addMetadataItemWithString:tag identifier:MP42MetadataKeyUnofficialASIN];
                }
            }
        }
        MP4ItmfItemListFree(list);
    }

    list = MP4ItmfGetItemsByMeaning(sourceHandle, "com.apple.iTunes", "ABRIDGED");
    if (list) {
        for (uint32_t i = 0; i < list->size; i++) {
            MP4ItmfItem *item = &list->elements[i];

            for (uint32_t j = 0; j < item->dataList.size; j++) {
                MP4ItmfData *data = &item->dataList.elements[j];
                NSString *tag = [[NSString alloc] initWithBytes:data->value length: data->valueSize encoding:NSUTF8StringEncoding];

                if (tag.length) {
                    [self addMetadataItemWithBool:[tag boolValue] identifier:MP42MetadataKeyUnofficialAbridged];
                }
            }
        }
        MP4ItmfItemListFree(list);
    }
}

- (void)writeiTunEXTCMetadataWithFileHandle:(MP4FileHandle)fileHandle
                                metadataKey:(NSString *)metadataKey
                                  iTunesKey:(const char *)iTunesKey
{
    if (self.itemsMap[metadataKey]) {

        MP4ItmfItemList *list = MP4ItmfGetItemsByMeaning(fileHandle, "com.apple.iTunes", iTunesKey);
        if (list) {
            for (uint32_t i = 0; i < list->size; i++) {
                MP4ItmfItem *item = &list->elements[i];
                MP4ItmfRemoveItem(fileHandle, item);
            }
        }
        MP4ItmfItemListFree(list);

        MP4ItmfItem *newItem = MP4ItmfItemAlloc("----", 1);
        newItem->mean = strdup("com.apple.iTunes");
        newItem->name = strdup(iTunesKey);

        MP4ItmfData *data = &newItem->dataList.elements[0];

        NSString *value = self.itemsMap[metadataKey].stringValue;
        if (value) {
            data->typeCode = MP4_ITMF_BT_UTF8;
            size_t len = strlen(value.UTF8String);
            if (len < UINT32_MAX) {
                data->valueSize = (uint32_t)len;
                data->value = (uint8_t *)malloc(data->valueSize);
                memcpy(data->value, value.UTF8String, data->valueSize);

                MP4ItmfAddItem(fileHandle, newItem);
            }
        }

        MP4ItmfItemFree(newItem);
    } else {
        MP4ItmfItemList *list = MP4ItmfGetItemsByMeaning(fileHandle, "com.apple.iTunes", iTunesKey);
        if (list) {
            for (uint32_t i = 0; i < list->size; i++) {
                MP4ItmfItem *item = &list->elements[i];
                MP4ItmfRemoveItem(fileHandle, item);
            }
        }

        MP4ItmfItemListFree(list);
    }
}

- (void)writeMetadataWithFileHandle:(MP4FileHandle)fileHandle
{
    NSParameterAssert(fileHandle);

    if (self.isEdited == NO && self.isArtworkEdited == NO) {
        return;
    }

    const MP4Tags *tags = MP4TagsAlloc();
    MP4TagsFetch(tags, fileHandle);

    MP4TagsSetName       (tags, self.itemsMap[MP42MetadataKeyName].stringValue.UTF8String);
    MP4TagsSetArtist     (tags, self.itemsMap[MP42MetadataKeyArtist].stringValue.UTF8String);
    MP4TagsSetAlbumArtist(tags, self.itemsMap[MP42MetadataKeyAlbumArtist].stringValue.UTF8String);
    MP4TagsSetAlbum      (tags, self.itemsMap[MP42MetadataKeyAlbum].stringValue.UTF8String);
    MP4TagsSetGrouping   (tags, self.itemsMap[MP42MetadataKeyGrouping].stringValue.UTF8String);
    MP4TagsSetComposer   (tags, self.itemsMap[MP42MetadataKeyComposer].stringValue.UTF8String);
    MP4TagsSetComments   (tags, self.itemsMap[MP42MetadataKeyUserComment].stringValue.UTF8String);

    uint16_t genreType = genreIndexFromString(self.itemsMap[MP42MetadataKeyUserGenre].stringValue);
    if (genreType) {
        MP4TagsSetGenre(tags, NULL);
        MP4TagsSetGenreType(tags, &genreType);
    }
    else {
        MP4TagsSetGenreType(tags, NULL);
        MP4TagsSetGenre(tags, self.itemsMap[MP42MetadataKeyUserGenre].stringValue.UTF8String);
    }

    MP4TagsSetReleaseDate(tags, self.itemsMap[MP42MetadataKeyReleaseDate].stringValue.UTF8String);

    if (self.itemsMap[MP42MetadataKeyTrackNumber]) {
        NSArray<NSNumber *> *track = (NSArray<NSNumber *> *)self.itemsMap[MP42MetadataKeyTrackNumber].value;
        MP4TagTrack dtrack;
        dtrack.index = track[0].intValue;
        dtrack.total = track[1].intValue;
        MP4TagsSetTrack(tags, &dtrack);
    }
    else {
        MP4TagsSetTrack(tags, NULL);
    }
    
    if (self.itemsMap[MP42MetadataKeyDiscNumber]) {
        NSArray<NSNumber *> *disk = (NSArray<NSNumber *> *)self.itemsMap[MP42MetadataKeyDiscNumber].value;
        MP4TagDisk ddisk;
        ddisk.index = disk[0].intValue;
        ddisk.total = disk[1].intValue;
        MP4TagsSetDisk(tags, &ddisk);
    }
    else {
        MP4TagsSetDisk(tags, NULL);
    }
    
    if (self.itemsMap[MP42MetadataKeyBeatsPerMin]) {
        const uint16_t i = self.itemsMap[MP42MetadataKeyBeatsPerMin].numberValue.intValue;
        MP4TagsSetTempo(tags, &i);
    }
    else {
        MP4TagsSetTempo(tags, NULL);
    }

    MP4TagsSetTrackSubTitle    (tags, self.itemsMap[MP42MetadataKeyTrackSubTitle].stringValue.UTF8String);
    MP4TagsSetSongDescription  (tags, self.itemsMap[MP42MetadataKeySongDescription].stringValue.UTF8String);
    MP4TagsSetDirector         (tags, self.itemsMap[MP42MetadataKeyDirector].stringValue.UTF8String);
    MP4TagsSetArtDirector      (tags, self.itemsMap[MP42MetadataKeyArtDirector].stringValue.UTF8String);
    MP4TagsSetArranger         (tags, self.itemsMap[MP42MetadataKeyArranger].stringValue.UTF8String);
    MP4TagsSetLyricist         (tags, self.itemsMap[MP42MetadataKeyAuthor].stringValue.UTF8String);
    MP4TagsSetAcknowledgement  (tags, self.itemsMap[MP42MetadataKeyAcknowledgement].stringValue.UTF8String);
    MP4TagsSetConductor        (tags, self.itemsMap[MP42MetadataKeyConductor].stringValue.UTF8String);
    MP4TagsSetLinearNotes      (tags, self.itemsMap[MP42MetadataKeyLinerNotes].stringValue.UTF8String);
    MP4TagsSetRecordCompany    (tags, self.itemsMap[MP42MetadataKeyRecordCompany].stringValue.UTF8String);
    MP4TagsSetOriginalArtist   (tags, self.itemsMap[MP42MetadataKeyOriginalArtist].stringValue.UTF8String);
    MP4TagsSetPhonogramRights  (tags, self.itemsMap[MP42MetadataKeyPhonogramRights].stringValue.UTF8String);
    MP4TagsSetProducer         (tags, self.itemsMap[MP42MetadataKeySongProducer].stringValue.UTF8String);
    MP4TagsSetPerformer        (tags, self.itemsMap[MP42MetadataKeyPerformer].stringValue.UTF8String);
    MP4TagsSetPublisher        (tags, self.itemsMap[MP42MetadataKeyPublisher].stringValue.UTF8String);
    MP4TagsSetSoundEngineer    (tags, self.itemsMap[MP42MetadataKeySoundEngineer].stringValue.UTF8String);
    MP4TagsSetSoloist          (tags, self.itemsMap[MP42MetadataKeySoloist].stringValue.UTF8String);

    if (self.itemsMap[MP42MetadataKeyDiscCompilation]) {
        uint8_t value = self.itemsMap[MP42MetadataKeyDiscCompilation].numberValue.intValue;
        MP4TagsSetCompilation(tags, &value);
    }

    MP4TagsSetCredits          (tags, self.itemsMap[MP42MetadataKeyCredits].stringValue.UTF8String);
    MP4TagsSetThanks           (tags, self.itemsMap[MP42MetadataKeyThanks].stringValue.UTF8String);
    MP4TagsSetOnlineExtras     (tags, self.itemsMap[MP42MetadataKeyOnlineExtras].stringValue.UTF8String);
    MP4TagsSetExecutiveProducer(tags, self.itemsMap[MP42MetadataKeyExecProducer].stringValue.UTF8String);

    // Movements keys
    if (self.itemsMap[MP42MetadataKeyShowWorkAndMovement]) {
        const uint8_t value = self.itemsMap[MP42MetadataKeyShowWorkAndMovement].numberValue.intValue ? 1 : 0;
        MP4TagsSetShowWorkAndMovement(tags, &value);
    }
    else {
        MP4TagsSetShowWorkAndMovement(tags, NULL);
    }

    MP4TagsSetWorkName(tags, self.itemsMap[MP42MetadataKeyWorkName].stringValue.UTF8String);
    MP4TagsSetMovementName(tags, self.itemsMap[MP42MetadataKeyMovementName].stringValue.UTF8String);

    if (self.itemsMap[MP42MetadataKeyMovementNumber]) {
        const uint16_t value = self.itemsMap[MP42MetadataKeyMovementNumber].numberValue.intValue;
        MP4TagsSetMovementNumber(tags, &value);
    }
    else {
        MP4TagsSetMovementNumber(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyMovementCount]) {
        const uint16_t value = self.itemsMap[MP42MetadataKeyMovementCount].numberValue.intValue;
        MP4TagsSetMovementCount(tags, &value);
    }
    else {
        MP4TagsSetMovementCount(tags, NULL);
    }

    // TV Show Specifics
    MP4TagsSetTVShow           (tags, self.itemsMap[MP42MetadataKeyTVShow].stringValue.UTF8String);
    MP4TagsSetTVNetwork        (tags, self.itemsMap[MP42MetadataKeyTVNetwork].stringValue.UTF8String);
    MP4TagsSetTVEpisodeID      (tags, self.itemsMap[MP42MetadataKeyTVEpisodeID].stringValue.UTF8String);

    if (self.itemsMap[MP42MetadataKeyTVSeason]) {
        const uint32_t value = self.itemsMap[MP42MetadataKeyTVSeason].numberValue.intValue;
        MP4TagsSetTVSeason(tags, &value);
    }
    else {
        MP4TagsSetTVSeason(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyTVEpisodeNumber]) {
        const uint32_t i = self.itemsMap[MP42MetadataKeyTVEpisodeNumber].numberValue.intValue;
        MP4TagsSetTVEpisode(tags, &i);
    }
    else {
        MP4TagsSetTVEpisode(tags, NULL);
    }

    MP4TagsSetDescription       (tags, self.itemsMap[MP42MetadataKeyDescription].stringValue.UTF8String);
    MP4TagsSetLongDescription   (tags, self.itemsMap[MP42MetadataKeyLongDescription].stringValue.UTF8String);
    MP4TagsSetSeriesDescription (tags, self.itemsMap[MP42MetadataKeySeriesDescription].stringValue.UTF8String);
    MP4TagsSetLyrics            (tags, self.itemsMap[MP42MetadataKeyLyrics].stringValue.UTF8String);
    MP4TagsSetCopyright         (tags, self.itemsMap[MP42MetadataKeyCopyright].stringValue.UTF8String);
    MP4TagsSetEncodingTool      (tags, self.itemsMap[MP42MetadataKeyEncodingTool].stringValue.UTF8String);
    MP4TagsSetEncodedBy         (tags, self.itemsMap[MP42MetadataKeyEncodedBy].stringValue.UTF8String);
    MP4TagsSetPurchaseDate      (tags, self.itemsMap[MP42MetadataKeyPurchasedDate].stringValue.UTF8String);
    MP4TagsSetITunesAccount     (tags, self.itemsMap[MP42MetadataKeyAppleID].stringValue.UTF8String);

    if (self.itemsMap[MP42MetadataKeyMediaKind]) {
        const uint8_t value = self.itemsMap[MP42MetadataKeyMediaKind].numberValue.intValue;
        MP4TagsSetMediaType(tags, &value);
    }
    else {
        MP4TagsSetMediaType(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyMediaKind].numberValue.intValue == 21) {
        const uint8_t value = 1;
        MP4TagsSetPodcast(tags, &value);
    }
    else {
        MP4TagsSetPodcast(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyMediaKind].numberValue.intValue == 23) {
        const uint8_t value = 1;
        MP4TagsSetITunesU(tags, &value);
    }
    else {
        MP4TagsSetITunesU(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyHDVideo]) {
        const uint8_t value = self.itemsMap[MP42MetadataKeyHDVideo].numberValue.intValue;
        MP4TagsSetHDVideo(tags, &value);
    }
    else {
        MP4TagsSetHDVideo(tags, NULL);
    }
    
    if (self.itemsMap[MP42MetadataKeyGapless]) {
        const uint8_t value = self.itemsMap[MP42MetadataKeyGapless].numberValue.intValue;
        MP4TagsSetGapless(tags, &value);
    }
    else {
        MP4TagsSetGapless(tags, NULL);
    }
    
    if (self.itemsMap[MP42MetadataKeyPodcast]) {
        const uint8_t value = self.itemsMap[MP42MetadataKeyPodcast].numberValue.intValue;
        MP4TagsSetPodcast(tags, &value);
    }
    else {
        MP4TagsSetPodcast(tags, NULL);
    }

    MP4TagsSetKeywords(tags, self.itemsMap[MP42MetadataKeyKeywords].stringValue.UTF8String);
    MP4TagsSetCategory(tags, self.itemsMap[MP42MetadataKeyCategory].stringValue.UTF8String);

    if (self.itemsMap[MP42MetadataKeyContentRating]) {
        const uint8_t value = self.itemsMap[MP42MetadataKeyContentRating].numberValue.intValue;
        MP4TagsSetContentRating(tags, &value);
    }
    else {
        MP4TagsSetContentRating(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyAccountCountry]) {
        const uint32_t i = self.itemsMap[MP42MetadataKeyAccountCountry].numberValue.intValue;
        MP4TagsSetITunesCountry(tags, &i);
    }
    else {
        MP4TagsSetITunesCountry(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyContentID]) {
        const uint32_t i = self.itemsMap[MP42MetadataKeyContentID].numberValue.intValue;
        MP4TagsSetContentID(tags, &i);
    }
    else {
        MP4TagsSetContentID(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyGenreID]) {
        const uint32_t i = self.itemsMap[MP42MetadataKeyGenreID].numberValue.intValue;
        MP4TagsSetGenreID(tags, &i);
    }
    else {
        MP4TagsSetGenreID(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyArtistID]) {
        const uint32_t i = self.itemsMap[MP42MetadataKeyArtistID].numberValue.intValue;
        MP4TagsSetArtistID(tags, &i);
    }
    else {
        MP4TagsSetArtistID(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyPlaylistID]) {
        const uint64_t i = self.itemsMap[MP42MetadataKeyPlaylistID].numberValue.integerValue;
        MP4TagsSetPlaylistID(tags, &i);
    }
    else {
        MP4TagsSetPlaylistID(tags, NULL);
    }

    if (self.itemsMap[MP42MetadataKeyComposerID]) {
        const uint32_t i = self.itemsMap[MP42MetadataKeyComposerID].numberValue.intValue;
        MP4TagsSetComposerID(tags, &i);
    }
    else {
        MP4TagsSetComposerID(tags, NULL);
    }

    MP4TagsSetXID            (tags, self.itemsMap[MP42MetadataKeyXID].stringValue.UTF8String);
    MP4TagsSetSortName       (tags, self.itemsMap[MP42MetadataKeySortName].stringValue.UTF8String);
    MP4TagsSetSortArtist     (tags, self.itemsMap[MP42MetadataKeySortArtist].stringValue.UTF8String);
    MP4TagsSetSortAlbumArtist(tags, self.itemsMap[MP42MetadataKeySortAlbumArtist].stringValue.UTF8String);
    MP4TagsSetSortAlbum      (tags, self.itemsMap[MP42MetadataKeySortAlbum].stringValue.UTF8String);
    MP4TagsSetSortComposer   (tags, self.itemsMap[MP42MetadataKeySortComposer].stringValue.UTF8String);
    MP4TagsSetSortTVShow     (tags, self.itemsMap[MP42MetadataKeySortTVShow].stringValue.UTF8String);

    if (self.isArtworkEdited) {

        for (uint32_t j = 0; j < tags->artworkCount; j++) {
            MP4TagsRemoveArtwork(tags, j);
        }

        NSArray<MP42MetadataItem *> *artworks = [self metadataItemsFilteredByIdentifier:MP42MetadataKeyCoverArt];
        for (uint32_t i = 0; i < artworks.count; i++) {
            MP42Image *artwork = (MP42Image *)artworks[i].value;

            if (artwork.data && artwork.data.length < UINT32_MAX) {
                MP4TagArtwork newArtwork;
                newArtwork.data = (void *)artwork.data.bytes;
                newArtwork.size = (uint32_t)artwork.data.length;
                newArtwork.type = (MP4TagArtworkType)artwork.type;

                if (tags->artworkCount > i) {
                    MP4TagsSetArtwork(tags, i, &newArtwork);
                } else {
                    MP4TagsAddArtwork(tags, &newArtwork);
                }
            }
        }
    }

    MP4TagsStore(tags, fileHandle);
    MP4TagsFree(tags);

    // Rewrite extended metadata using the generic iTMF api
    if (self.itemsMap[MP42MetadataKeyRating]) {

        MP4ItmfItemList *list = MP4ItmfGetItemsByMeaning(fileHandle, "com.apple.iTunes", "iTunEXTC");
        if (list) {
            for (uint32_t i = 0; i < list->size; i++) {
                MP4ItmfItem *item = &list->elements[i];
                MP4ItmfRemoveItem(fileHandle, item);
            }
        }
        MP4ItmfItemListFree(list);

        MP4ItmfItem *newItem = MP4ItmfItemAlloc("----", 1);
        newItem->mean = strdup("com.apple.iTunes");
        newItem->name = strdup("iTunEXTC");

        MP4ItmfData *data = &newItem->dataList.elements[0];

        NSString *ratingString = self.itemsMap[MP42MetadataKeyRating].stringValue;
        NSString *ratingAnnotation = self.itemsMap[MP42MetadataKeyRatingAnnotation].stringValue;

        if (ratingAnnotation.length && ratingString.length) {
			ratingString = [NSString stringWithFormat:@"%@%@", ratingString, ratingAnnotation];
		}

        if (ratingString) {
            data->typeCode = MP4_ITMF_BT_UTF8;
            size_t len = strlen(ratingString.UTF8String);
            if (len < UINT32_MAX) {
                data->valueSize = (uint32_t)len;
                data->value = (uint8_t *)malloc(data->valueSize);
                memcpy(data->value, ratingString.UTF8String, data->valueSize);

                MP4ItmfAddItem(fileHandle, newItem);
            }
        }

        MP4ItmfItemFree(newItem);

    } else {
        MP4ItmfItemList *list = MP4ItmfGetItemsByMeaning(fileHandle, "com.apple.iTunes", "iTunEXTC");
        if (list) {
            for (uint32_t i = 0; i < list->size; i++) {
                MP4ItmfItem *item = &list->elements[i];
                MP4ItmfRemoveItem(fileHandle, item);
            }
        }

        MP4ItmfItemListFree(list);
    }

    MP4ItmfItemList *list = MP4ItmfGetItemsByMeaning(fileHandle, "com.apple.iTunes", "iTunMOVI");
    NSMutableDictionary *iTunMovi = [[NSMutableDictionary alloc] init];;
    if (list) {
        uint32_t i;
        for (i = 0; i < list->size; i++) {
            MP4ItmfItem* item = &list->elements[i];
            uint32_t j;
            for(j = 0; j < item->dataList.size; j++) {
                MP4ItmfData* data = &item->dataList.elements[j];
                NSData *xmlData = [NSData dataWithBytes:data->value length:data->valueSize];
                NSDictionary *dma = (NSDictionary *)[NSPropertyListSerialization propertyListWithData:xmlData
                                                                                              options:NSPropertyListMutableContainersAndLeaves
                                                                                               format:nil error:NULL];
                iTunMovi = [dma mutableCopy];
            }
        }
        MP4ItmfItemListFree(list);
    }

    if (iTunMovi) {
        if (self.itemsMap[MP42MetadataKeyCast]) {
            [iTunMovi setObject:[self dictArrayFromStringArray:self.itemsMap[MP42MetadataKeyCast].arrayValue key:@"name"] forKey:@"cast"];
        }
        else {
            [iTunMovi removeObjectForKey:@"cast"];
        }

        if (self.itemsMap[MP42MetadataKeyDirector]) {
            [iTunMovi setObject:[self dictArrayFromStringArray:self.itemsMap[MP42MetadataKeyDirector].arrayValue key:@"name"] forKey:@"directors"];
        }
        else {
            [iTunMovi removeObjectForKey:@"directors"];
        }

        if (self.itemsMap[MP42MetadataKeyCodirector]) {
            [iTunMovi setObject:[self dictArrayFromStringArray:self.itemsMap[MP42MetadataKeyCodirector].arrayValue key:@"name"] forKey:@"codirectors"];
        }
        else {
            [iTunMovi removeObjectForKey:@"codirectors"];
        }

        if (self.itemsMap[MP42MetadataKeyProducer]) {
            [iTunMovi setObject:[self dictArrayFromStringArray:self.itemsMap[MP42MetadataKeyProducer].arrayValue key:@"name"] forKey:@"producers"];
        }
        else {
            [iTunMovi removeObjectForKey:@"producers"];
        }

        if (self.itemsMap[MP42MetadataKeyScreenwriters]) {
            [iTunMovi setObject:[self dictArrayFromStringArray:self.itemsMap[MP42MetadataKeyScreenwriters].arrayValue key:@"name"] forKey:@"screenwriters"];
        }
        else {
            [iTunMovi removeObjectForKey:@"screenwriters"];
        }

        if (self.itemsMap[MP42MetadataKeyStudio]) {
            [iTunMovi setObject:self.itemsMap[MP42MetadataKeyStudio].stringValue forKey:@"studio"];
        }
        else {
            [iTunMovi removeObjectForKey:@"studio"];
        }

        NSData *serializedPlist = [NSPropertyListSerialization dataWithPropertyList:iTunMovi
                                                   format:NSPropertyListXMLFormat_v1_0
                                                  options:0 error:NULL];
        if (iTunMovi.count) {
            MP4ItmfItemList *moviList = MP4ItmfGetItemsByMeaning(fileHandle, "com.apple.iTunes", "iTunMOVI");
            if (moviList) {
                uint32_t i;
                for (i = 0; i < moviList->size; i++) {
                    MP4ItmfItem *item = &moviList->elements[i];
                    MP4ItmfRemoveItem(fileHandle, item);
                }
            }
            MP4ItmfItemListFree(moviList);

            MP4ItmfItem *newItem = MP4ItmfItemAlloc( "----", 1 );
            newItem->mean = strdup( "com.apple.iTunes" );
            newItem->name = strdup( "iTunMOVI" );

            MP4ItmfData *data = &newItem->dataList.elements[0];
            data->typeCode = MP4_ITMF_BT_UTF8;
            if (serializedPlist.length < UINT32_MAX) {
                data->valueSize = (uint32_t)serializedPlist.length;
                data->value = (uint8_t*)malloc(data->valueSize);
                memcpy(data->value, serializedPlist.bytes, data->valueSize);
            }

            MP4ItmfAddItem(fileHandle, newItem);
            MP4ItmfItemFree(newItem);
        }
        else {
            MP4ItmfItemList* moviList = MP4ItmfGetItemsByMeaning(fileHandle, "com.apple.iTunes", "iTunMOVI");
            if (moviList) {
                uint32_t i;
                for (i = 0; i < moviList->size; i++) {
                    MP4ItmfItem *item = &moviList->elements[i];
                    MP4ItmfRemoveItem(fileHandle, item);
                }
            }
            MP4ItmfItemListFree(moviList);
        }
    }

    [self writeiTunEXTCMetadataWithFileHandle:fileHandle
                                  metadataKey:MP42MetadataKeyUnofficialSubtitle
                                    iTunesKey:"SUBTITLE"];
    [self writeiTunEXTCMetadataWithFileHandle:fileHandle
                                  metadataKey:MP42MetadataKeyUnofficialLanguage
                                    iTunesKey:"LANGUAGE"];
    [self writeiTunEXTCMetadataWithFileHandle:fileHandle
                                  metadataKey:MP42MetadataKeyUnofficialASIN
                                    iTunesKey:"ASIN"];
    [self writeiTunEXTCMetadataWithFileHandle:fileHandle
                                  metadataKey:MP42MetadataKeyUnofficialAbridged
                                    iTunesKey:"ABRIDGED"];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

#define MP42METADATA_CODER_VERSION 6

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt:MP42METADATA_CODER_VERSION forKey:@"MP42TagEncodeVersion"];
    [coder encodeObject:_itemsArray forKey:@"MP42Items"];
    [coder encodeBool:_artworkEdited forKey:@"MP42ArtworkEdited"];
    [coder encodeBool:_edited forKey:@"MP42Edited"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [self init];

    NSInteger version = [decoder decodeIntForKey:@"MP42TagEncodeVersion"];

    if (version > MP42METADATA_CODER_VERSION)
    {
        return nil;
    }

    _itemsArray = [decoder decodeObjectOfClasses:[NSSet setWithObjects:[NSMutableArray class], [MP42MetadataItem class], nil]
                                              forKey:@"MP42Items"];

    _artworkEdited = [decoder decodeBoolForKey:@"MP42ArtworkEdited"];
    _edited = [decoder decodeBoolForKey:@"MP42Edited"];

    for (MP42MetadataItem *item in _itemsArray) {
        if (![item.identifier isEqualToString:MP42MetadataKeyCoverArt]) {
            _itemsMap[item.identifier] = item;
        }
    }

    return self;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    MP42Metadata *newObject = [[MP42Metadata allocWithZone:zone] init];
    [newObject mergeMetadata:self];
    return newObject;
}

@end
