//
//  MP42File.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42File.h"
#import "MP42FileImporter.h"
#import "MP42Muxer.h"
#import "MP42PrivateUtilities.h"
#import "MP42Languages.h"
#import "MP42Track+Private.h"
#import "MP42PreviewGenerator.h"
#import "MP42Metadata+Private.h"
#import "MP42RelatedItem.h"

#import "mp4v2.h"

NSString * const MP4264BitData = @"MP4264BitData";
NSString * const MP4264BitTime = @"MP4264BitTime";
NSString * const MP42GenerateChaptersPreviewTrack = @"MP42ChaptersPreview";
NSString * const MP42ChaptersPreviewPosition = @"MP42ChaptersPreviewPosition";
NSString * const MP42CustomChaptersPreviewTrack = @"MP42CustomChaptersPreview";
NSString * const MP42ForceHvc1 = @"MP42ForceHvc1";

/**
 *  MP42Status
 */
typedef NS_ENUM(NSUInteger, MP42Status) {
    MP42StatusLoaded = 0,
    MP42StatusReading,
    MP42StatusWriting
};

static id <MP42Logging> _logger = nil;

static void logCallback(MP4LogLevel loglevel, const char *fmt, va_list ap) {
    const char *level;

    switch (loglevel) {
        case 0:
            level = "None";
            break;
        case 1:
            level = "Error";
            break;
        case 2:
            level = "Warning";
            break;
        case 3:
            level = "Info";
            break;
        case 4:
            level = "Verbose1";
            break;
        case 5:
            level = "Verbose2";
            break;
        case 6:
            level = "Verbose3";
            break;
        case 7:
            level = "Verbose4";
            break;
        default:
            level = "Unknown";
            break;
    }
    char buffer[2048];
    vsnprintf(buffer, 2048, fmt, ap);
    NSString *output = [NSString stringWithFormat:@"%s: %s", level, buffer];

    [_logger writeToLog:output];
}

@interface MP42File () <MP42MuxerDelegate> {
    NSMutableArray<__kindof MP42Track *>  *_tracks;
    NSMutableArray<MP42Track *>  *_tracksToBeDeleted;
}

@property(nonatomic, readwrite) MP42FileHandle fileHandle;
@property(nonatomic, readwrite) NSURL *URL;
@property(nonatomic, readwrite) NSData *fileURLBookmark;

@property(nonatomic, readwrite) NSMutableArray<NSURL *> *importersURL;
@property(nonatomic, readwrite) NSMutableArray<NSData *> *importersBookmarks;

@property(nonatomic, readonly) NSMutableArray<__kindof MP42Track *> *itracks;
@property(nonatomic, readonly) NSMutableDictionary<NSString *, MP42FileImporter *> *importers;

@property(nonatomic, readwrite) MP42Status status;
@property(nonatomic, readwrite) MP42Muxer *muxer;

@end

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42File

@synthesize itracks = _tracks;

+ (void)initialize {
    if (self == [MP42File class]) {
        MP4SetLogCallback(logCallback);
        MP4LogSetLevel(MP4_LOG_INFO);
    }
}

+ (void)setGlobalLogger:(id<MP42Logging>)logger
{
    _logger = logger;
}

- (BOOL)startReading {
    NSAssert(self.fileHandle == MP4_INVALID_FILE_HANDLE, @"File Handle already open");
    _fileHandle = MP4Read(self.URL.fileSystemRepresentation);

    if (self.fileHandle != MP4_INVALID_FILE_HANDLE) {
        self.status = MP42StatusReading;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)stopReading {
    BOOL returnValue = MP4Close(_fileHandle, 0);
    self.fileHandle = MP4_INVALID_FILE_HANDLE;
    self.status = MP42StatusLoaded;
    return returnValue;
}

- (BOOL)startWriting {
    NSAssert(self.fileHandle == MP4_INVALID_FILE_HANDLE, @"File Handle already open");
    _fileHandle = MP4Modify(self.URL.fileSystemRepresentation, 0);

    if (self.fileHandle != MP4_INVALID_FILE_HANDLE) {
        self.status = MP42StatusWriting;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)stopWriting {
    return [self stopReading];
}

#pragma mark - Inits

- (instancetype)init {
    if ((self = [super init])) {
        _hasFileRepresentation = NO;
        _tracks = [[NSMutableArray alloc] init];
        _tracksToBeDeleted = [[NSMutableArray alloc] init];

        _metadata = [[MP42Metadata alloc] init];
        _importers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)URL error:(NSError * _Nullable __autoreleasing *)error {
    self = [super init];
    if (self) {
        _URL = URL.fileReferenceURL;

        // Open the file for reading
        if (![self startReading]) {

            if (error) {
                *error = MP42Error(MP42LocalizedString(@"The movie could not be opened.", @"error message"),
                                   MP42LocalizedString(@"The file is not a mp4 file.", @"error message"), 100);
                [_logger writeErrorToLog:*error];
            }
			return nil;
        }

        // Check the major brand
        // and refuse to open mov movies.
        const char *brand = NULL;
        MP4GetStringProperty(_fileHandle, "ftyp.majorBrand", &brand);
        if (brand != NULL) {
            if (!strcmp(brand, "qt  ")) {
                [self stopReading];

                if (error) {
                    *error = MP42Error(MP42LocalizedString(@"Invalid File Type.", @"error message"),
                                       MP42LocalizedString(@"MOV File cannot be edited.", @"error message"), 100);
                    [_logger writeErrorToLog:*error];
                }

                return nil;
            }
        }

        // Refuse to open fragmented mp4
        if (MP4HaveAtom(_fileHandle, "moof")) {
            [self stopReading];

            if (error) {
                *error = MP42Error(MP42LocalizedString(@"Invalid File Type.", @"error message"),
                                   MP42LocalizedString(@"Fragmented MP4 cannot be edited.", @"error message"), 100);
                [_logger writeErrorToLog:*error];
            }

            return nil;
        };

        // Wraps the tracks in obj-c objects
        _tracks = [[NSMutableArray alloc] init];
        uint32_t tracksCount = MP4GetNumberOfTracks(_fileHandle, 0, 0);
        MP4TrackId chapterId = findChapterTrackId(_fileHandle);
        MP4TrackId previewsId = findChapterPreviewTrackId(_fileHandle);

        for (uint32_t i = 0; i < tracksCount; i++) {
            id track;
            MP4TrackId trackId = MP4FindTrackId(_fileHandle, i, 0, 0);
            const char *type = MP4GetTrackType(_fileHandle, trackId);

            if (MP4_IS_AUDIO_TRACK_TYPE(type)) {
                track = [MP42AudioTrack alloc];
            } else if (MP4_IS_VIDEO_TRACK_TYPE(type)) {
                track = [MP42VideoTrack alloc];
            } else if (!strcmp(type, MP4_TEXT_TRACK_TYPE)) {
                if (trackId == chapterId) {
                    track = [MP42ChapterTrack alloc];
                } else {
                    track = [MP42SubtitleTrack alloc];
                }
            } else if (!strcmp(type, MP4_SUBTITLE_TRACK_TYPE)) {
                track = [MP42SubtitleTrack alloc];
            } else if (!strcmp(type, MP4_SUBPIC_TRACK_TYPE)) {
                track = [MP42SubtitleTrack alloc];
            } else if (!strcmp(type, MP4_CC_TRACK_TYPE)) {
                track = [MP42ClosedCaptionTrack alloc];
            } else {
                track = [MP42Track alloc];
            }

            track = [track initWithSourceURL:_URL trackID:trackId fileHandle:_fileHandle];
            [_tracks addObject:track];
        }

        // Restore the tracks references in the wrapped tracks
        [self reconnectReferences];

        // Load the previews images
        [self loadPreviewsFromTrackID:previewsId];

        // Load the metadata
        _metadata = [[MP42Metadata alloc] initWithFileHandle:_fileHandle];

        // Initialize things
        _hasFileRepresentation = YES;
        _tracksToBeDeleted = [[NSMutableArray alloc] init];
        _importers = [[NSMutableDictionary alloc] init];

        // Close the file
        [self stopReading];
	}

	return self;
}

/**
 *  Loads the tracks references and convert them
 *  to objects references
 */
- (void)reconnectReferences {
    for (MP42Track *ref in self.itracks) {
        if ([ref isMemberOfClass:[MP42AudioTrack class]]) {
            MP42AudioTrack *a = (MP42AudioTrack *)ref;
            if (a.fallbackTrackId) {
                a.fallbackTrack = [self trackWithTrackID:a.fallbackTrackId];
            }
            if (a.followsTrackId) {
                a.followsTrack = [self trackWithTrackID:a.followsTrackId];
            }
        }
        if ([ref isMemberOfClass:[MP42SubtitleTrack class]]) {
            MP42SubtitleTrack *a = (MP42SubtitleTrack *)ref;
            if (a.forcedTrackId) {
                a.forcedTrack = [self trackWithTrackID:a.forcedTrackId];
            }
        }
    }
}

/**
 *  Load the previews image from a track
 *
 *  @param trackID the id of the previews track
 */
- (void)loadPreviewsFromTrackID:(MP4TrackId)trackID {
    MP42Track *track = [self trackWithTrackID:trackID];
    if (track) {
        MP4SampleId sampleNum = MP4GetTrackNumberOfSamples(self.fileHandle, track.trackId);

        for (MP4SampleId currentSampleNum = 1; currentSampleNum <= sampleNum; currentSampleNum++) {
            uint8_t *pBytes = NULL;
            uint32_t numBytes = 0;
            MP4Duration duration;
            MP4Duration renderingOffset;
            MP4Timestamp pStartTime;
            unsigned char isSyncSample;

            if (!MP4ReadSample(self.fileHandle,
                               track.trackId,
                               currentSampleNum,
                               &pBytes, &numBytes,
                               &pStartTime, &duration, &renderingOffset,
                               &isSyncSample)) {
                break;
            }

            NSData *frameData = [[NSData alloc] initWithBytes:pBytes length:numBytes];
            MP42Image *frame = [[MP42Image alloc] initWithData:frameData type:MP42_ART_JPEG];

            if ([[self chapters].chapters count] >= currentSampleNum) {
                [[self chapters] chapterAtIndex:currentSampleNum - 1].image = frame;
            }

            free(pBytes);
        }
    }
}

#pragma mark - File Inspections

- (NSUInteger)duration {
    NSUInteger duration = 0;
    NSUInteger trackDuration = 0;
    for (MP42Track *track in self.itracks) {
        if ((trackDuration = [track duration]) > duration) {
            duration = trackDuration;
        }
    }
    return duration;
}

- (uint64_t)dataSize {
    uint64_t estimation = 0;
    for (MP42Track *track in self.itracks) {
        estimation += track.dataLength;
    }
    return estimation;
}

- (MP42ChapterTrack *)chapters {
    MP42ChapterTrack *chapterTrack = nil;

    for (MP42Track *track in self.itracks) {
        if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
            chapterTrack = (MP42ChapterTrack *)track;
        }
    }

    return chapterTrack;
}

- (NSArray<MP42Track *> *)tracks {
    return [NSArray arrayWithArray:self.itracks];
}

- (id)trackAtIndex:(NSUInteger)index {
    return [self.itracks objectAtIndex:index];
}

- (id)trackWithTrackID:(NSUInteger)trackID {
    for (MP42Track *track in self.itracks) {
        if (track.trackId == trackID) {
            return track;
        }
    }
    return nil;
}

- (NSSet<NSString *> *)languaguesForMediaType:(MP42MediaType)mediaType {
    NSMutableSet<NSString *> *languages = [NSMutableSet set];

    for (MP42Track *track in self.itracks) {
        if (track.mediaType == mediaType) {
            [languages addObject:track.language];
        }
    }

    return languages;
}

- (NSArray<MP42Track *> *)tracksWithMediaType:(MP42MediaType)mediaType {
    NSMutableArray<MP42Track *> *tracks = [NSMutableArray array];

    for (MP42Track *track in self.itracks) {
        if (track.mediaType == mediaType) {
            [tracks addObject:track];
        }
    }

    return tracks;
}

- (NSArray<MP42Track *> *)tracksWithMediaTypes:(NSArray *)mediaType {
    NSMutableArray<MP42Track *> *tracks = [NSMutableArray array];

    for (MP42Track *track in self.itracks) {
        if ([mediaType containsObject:@(track.mediaType)]) {
            [tracks addObject:track];
        }
    }

    return tracks;
}

- (NSArray<MP42Track *> *)tracksWithMediaType:(MP42MediaType)mediaType language:(NSString *)language {
    NSMutableArray<MP42Track *> *tracks = [NSMutableArray array];

    for (MP42Track *track in self.itracks) {
        if (track.mediaType == mediaType &&
            [track.language isEqualToString:language]) {
                [tracks addObject:track];
        }
    }

    return tracks;
}

- (NSArray<NSArray<MP42Track *> *> *)tracksSubgroupsWithMediaType:(MP42MediaType)mediaType {
    NSSet<NSString *> *languages = [self languaguesForMediaType:mediaType];
    NSMutableArray<NSArray<MP42Track *> *> *result = [NSMutableArray array];

    for (NSString *language in languages) {
        NSArray<MP42Track *> *tracks = [self tracksWithMediaType:mediaType language:language];
        NSMutableArray<MP42Track *> *mutableTracks = [tracks mutableCopy];

        for (MP42Track *track in tracks) {
            NSArray<MP42Track *> *relatedTracks = [self relatedTracksForTrack:track];
            [mutableTracks removeObjectsInArray:relatedTracks];
        }

        [result addObject:mutableTracks];
    }

    return result;
}

#pragma mark - Editing

- (void)addTrack:(MP42Track *)track {
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to add a track while the file is open for writing");
    NSAssert(![self.itracks containsObject:track], @"Unsupported operation: trying to add a track that is already present.");

    track.sourceId = track.trackId;
    track.trackId = 0;
    track.muxed = NO;
    track.edited = YES;

    track.language = track.language;
    track.name = track.name;
    if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
        for (id previousTrack in self.itracks)
            if ([previousTrack isMemberOfClass:[MP42ChapterTrack class]]) {
                [self.itracks removeObject:previousTrack];
                break;
        }
    }

    if (trackNeedConversion(track.format) && ![track isMemberOfClass:[MP42ChapterTrack class]]) {
        NSAssert(track.conversionSettings, @"Missing conversion settings");
    }

    if (track.importer && track.URL) {
        if (self.importers[track.URL.path]) {
            track.importer = self.importers[track.URL.path];
        } else {
            self.importers[track.URL.path] = track.importer;
        }
    }

    if ([track isMemberOfClass:[MP42AudioTrack class]]) {
        MP42AudioTrack *audioTrack = (MP42AudioTrack *)track;
        MP42Track *fallbackTrack = audioTrack.fallbackTrack;
        if (fallbackTrack && ![self.itracks containsObject:fallbackTrack]) {
            audioTrack.fallbackTrack = nil;
        }
    }

    if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
        track.duration = self.duration;
    }

    [self.itracks addObject:track];
}

- (void)removeTracks:(NSArray<MP42Track *> *)tracks {
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to remove a track while the file is open for writing");

    for (MP42Track *track in tracks) {
        // track is muxed, it needs to be removed from the file
        if (track.muxed)
            [_tracksToBeDeleted addObject:track];

        // Remove the reference
        for (MP42Track *ref in self.itracks) {
            if ([ref isMemberOfClass:[MP42AudioTrack class]]) {
                MP42AudioTrack *a = (MP42AudioTrack *)ref;
                if (a.fallbackTrack == track)
                    a.fallbackTrack = nil;
                if (a.followsTrack == track)
                    a.followsTrack = nil;
            }
            if ([ref isMemberOfClass:[MP42SubtitleTrack class]]) {
                MP42SubtitleTrack *a = (MP42SubtitleTrack *)ref;
                if (a.forcedTrack == track)
                    a.forcedTrack = nil;
            }
        }
    }

    [self.itracks removeObjectsInArray:tracks];
}

- (void)moveTrackAtIndex:(NSUInteger)index toIndex:(NSUInteger)newIndex {
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to move tracks while the file is open for writing");
    id track = [self.itracks objectAtIndex:index];

    [self.itracks removeObjectAtIndex:index];
    if (newIndex > self.itracks.count || newIndex > index) {
        newIndex--;
    }
    [self.itracks insertObject:track atIndex:newIndex];
}

- (void)moveTracks:(NSArray<MP42Track *> *)tracks toIndex:(NSUInteger)index {
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to move tracks while the file is open for writing");

    for (id track in tracks.reverseObjectEnumerator) {
        NSUInteger sourceIndex = [self.itracks indexOfObject:track];
        [self.itracks removeObjectAtIndex:sourceIndex];

        if (sourceIndex < index) {
            index--;
        }

        [self.itracks insertObject:track atIndex:index];
    }
}

- (void)organizeAlternateGroupsForMediaTypes:(NSArray *)mediaTypes withGroupID:(NSUInteger)groupID {
    NSArray<MP42Track *> *tracks = [self tracksWithMediaTypes:mediaTypes];
    BOOL enabled = NO;

    if (!tracks.count) {
        return;
    }

    for (MP42Track *track in tracks) {
        track.alternateGroup = groupID;

        if (track.enabled && !enabled) {
            enabled = YES;
        }
        else if (track.enabled) {
            track.enabled = NO;
        }
    }

    if (!enabled) {
        tracks.firstObject.enabled = YES;
    }
}

- (void)organizeAlternateGroups {
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to organize alternate groups while the file is open for writing");

    NSArray *typesToOrganize = @[@[@(kMP42MediaType_Video)],
                                @[@(kMP42MediaType_Audio)],
                                @[@(kMP42MediaType_Subtitle), @(kMP42MediaType_ClosedCaption)]];

    NSInteger index = 0;
    for (NSArray *types in typesToOrganize) {
        [self organizeAlternateGroupsForMediaTypes:types
                                      withGroupID:index];
        index += 1;
    }

    for (MP42Track *track in self.itracks) {
        if ([track isMemberOfClass:[MP42ChapterTrack class]])
            track.enabled = NO;
    }
}

- (void)inferMediaCharacteristics {
    MP42MediaType typesToOrganize[] = { kMP42MediaType_Video,
                                        kMP42MediaType_Audio,
                                        kMP42MediaType_Subtitle };

    for (NSUInteger i = 1; i < 3; i++) {
        [self organizeMediaCharacteristicsForMediaType:typesToOrganize[i]];
    }
}

- (void)inferTracksLanguages {
    for (MP42Track *track in self.itracks) {
        if ([track.language isEqualToString:@"zh"])
        {
            if ([track.name isEqualToString:@"Simplified"]) {
                track.language = @"zh-Hans";
            }
            else if ([track.name isEqualToString:@"Traditional"]) {
                track.language = @"zh-Hant";
            }
        }
    }
}

- (void)setTrack:(MP42Track *)track mediaCharacteristics:(NSSet<NSString *> *)tags {
    track.mediaCharacteristicTags = tags;

    for (MP42Track *relatedTrack in [self relatedTracksForTrack:track]) {
        relatedTrack.mediaCharacteristicTags = tags;
    }
}

- (NSArray<MP42Track *> *)relatedTracksForTrack:(MP42Track *)track {
    NSMutableArray *tracks = [NSMutableArray array];
    if ([track isKindOfClass:[MP42AudioTrack class]]) {
        MP42AudioTrack *audioTrack = (MP42AudioTrack *)track;
        MP42Track *fallbackTrack = audioTrack.fallbackTrack;
        if (fallbackTrack) {
            [tracks addObject:fallbackTrack];
        }
    }

    if ([track isKindOfClass:[MP42SubtitleTrack class]]) {
        MP42SubtitleTrack *subTrack = (MP42SubtitleTrack *)track;
        MP42Track *forcedTrack = subTrack.forcedTrack;
        if (forcedTrack) {
            [tracks addObject:forcedTrack];
        }
    }
    return tracks;
}

- (void)organizeMediaCharacteristicsForMediaType:(MP42MediaType)mediaType {
    NSArray<NSArray<MP42Track *> *> *subGroups = [self tracksSubgroupsWithMediaType:mediaType];

    for (NSArray<MP42Track *> *subGroup in subGroups) {

        for (MP42Track *track in subGroup) {
            NSMutableSet<NSString *> *tags = [track.mediaCharacteristicTags mutableCopy];

            if (tags.count) {
                continue;
            }

            NSString *lowercaseName = track.name.lowercaseString;

            // Try to create some useful tags from the track name.
            if ([lowercaseName containsString:@"director"] ||
                [lowercaseName containsString:@"commentary"] ||
                [lowercaseName containsString:@"lyric"] ||
                [lowercaseName containsString:@"karaoke"] ||
                [lowercaseName containsString:@"sign"]) {
                [tags addObject:@"public.auxiliary-content"];
            }

            if (mediaType == kMP42MediaType_Subtitle) {
                if ([lowercaseName containsString:@"lyric"] ||
                    [lowercaseName containsString:@"karaoke"]) {
                    [tags addObject:@"public.accessibility.describes-music-and-sound"];
                }
                if ([lowercaseName containsString:@"sdh"]) {
                    [tags addObject:@"public.accessibility.transcribes-spoken-dialog"];
                    [tags addObject:@"public.accessibility.describes-music-and-sound"];
                }
                if ([lowercaseName containsString:@"forced"]) {
                    [tags addObject:@"public.subtitles.forced-only"];
                }
            }

            [self setTrack:track mediaCharacteristics:tags];
        }

        // Now we got to find a main track
        MP42Track *mainTrackCandidate = nil;

        // First check if we have a track with no tag or main tag and a related track
        for (MP42Track *track in subGroup) {
            NSArray<MP42Track *> *relatedTracks = [self relatedTracksForTrack:track];
            if (relatedTracks.count && track.mediaCharacteristicTags.count == 0) {
                mainTrackCandidate = track;
                break;
            }
        }

        // If not use the first track with no tags
        if (!mainTrackCandidate) {
            for (MP42Track *track in subGroup) {
                if (track.mediaCharacteristicTags.count == 0 ||
                    [track.mediaCharacteristicTags containsObject:@"public.main-program-content"]) {
                    mainTrackCandidate = track;
                    break;
                }
            }
        }

        // If not use the first track with a related track
        for (MP42Track *track in subGroup) {
            NSArray<MP42Track *> *relatedTracks = [self relatedTracksForTrack:track];
            if (relatedTracks.count) {
                mainTrackCandidate = track;
                break;
            }
        }

        // Else use the first available track
        if (!mainTrackCandidate) {
            mainTrackCandidate = subGroup.firstObject;
        }

        NSMutableSet<NSString *> *tags = [mainTrackCandidate.mediaCharacteristicTags mutableCopy];
        [tags addObject:@"public.main-program-content"];
        [tags removeObject:@"public.auxiliary-content"];
        [self setTrack:mainTrackCandidate mediaCharacteristics:tags];

        for (MP42Track *track in subGroup) {
            if ([track.mediaCharacteristicTags containsObject:@"public.main-program-content"] == NO) {
                NSMutableSet<NSString *> *subGroupTags = [track.mediaCharacteristicTags mutableCopy];
                [subGroupTags addObject:@"public.auxiliary-content"];
                [self setTrack:track mediaCharacteristics:subGroupTags];
            }
        }
    }
}

#pragma mark - Editing internal

- (void)removeMuxedTrack:(MP42Track *)track {
    if (!self.fileHandle) {
        return;
    }

    // We have to handle a few special cases here.
    if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
        MP4ChapterType err = MP4DeleteChapters(self.fileHandle, MP4ChapterTypeAny, track.trackId);
        if (err == 0) {
            MP4DeleteTrack(self.fileHandle, track.trackId);
        }
    } else {
        MP4DeleteTrack(self.fileHandle, track.trackId);
    }

    updateTracksCount(self.fileHandle);
    updateMoovDuration(self.fileHandle);
}

#pragma mark - Saving

- (BOOL)optimize {
    __block BOOL noErr = NO;
    __block _Atomic int32_t done = 0;

    @autoreleasepool {
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        MP42RelatedItem *item = [[MP42RelatedItem alloc] initWithURL:self.URL extension:@"sublertemp"];

#ifdef SB_SANDBOX
        [NSFileCoordinator addFilePresenter:item];
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:item];

        if (item && coordinator) {
#else
        if (item) {
#endif

            unsigned long long originalFileSize = [[[fileManager attributesOfItemAtPath:self.URL.path error:nil] valueForKey:NSFileSize] unsignedLongLongValue];

            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                noErr = MP4Optimize(self.URL.fileSystemRepresentation, item.presentedItemURL.fileSystemRepresentation);
                done = 1;
                dispatch_semaphore_signal(sem);
            });

            // Loop to check the progress
            while (!done) {
                unsigned long long fileSize = [[[fileManager attributesOfItemAtPath:item.presentedItemURL.path error:nil] valueForKey:NSFileSize] unsignedLongLongValue];
                [self progressStatus:((double)fileSize / originalFileSize) * 100];
                usleep(450000);
            }

            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

            NSError *error;

            // Additional check to see if we can open the optimized file
            if (noErr && [[MP42File alloc] initWithURL:item.presentedItemURL error:NULL]) {
                // Replace the original file
                NSURL *result = nil;
                noErr = [fileManager replaceItemAtURL:self.URL
                                        withItemAtURL:item.presentedItemURL
                                       backupItemName:nil
                                              options:NSFileManagerItemReplacementWithoutDeletingBackupItem
                                     resultingItemURL:&result error:&error];
                if (noErr) {
                    self.URL = result;
                } else {
                    [_logger writeErrorToLog:error];
                }
            } else {
                [_logger writeToLog:@"Couldn't optimize file"];
            }

            if (!noErr) {
                // Remove the temp file if the optimization didn't complete
                [fileManager removeItemAtURL:item.presentedItemURL error:NULL];
            }

#ifdef SB_SANDBOX
            [NSFileCoordinator removeFilePresenter:item];
#endif
        }
    }

    return noErr;
}

- (void)cancel {
    [self.muxer cancel];
}

- (void)progressStatus:(double)progress {
    if (_progressHandler) {
        _progressHandler(progress);
    }
}

- (BOOL)writeToUrl:(NSURL *)url options:(nullable NSDictionary<NSString *, id> *)options error:(NSError * __autoreleasing *)outError {
    BOOL success = YES;

    if (!url) {
        if (outError) {
            *outError = MP42Error(MP42LocalizedString(@"Invalid path.", @"error message"),
                                  MP42LocalizedString(@"The destination path cannot be empty.", @"error message"), 100);
            [_logger writeErrorToLog:*outError];
        }
        return NO;
    }

    for (MP42Track *track in self.tracks) {
        NSURL *sourceURL = track.URL.filePathURL;
        if ([sourceURL isEqualTo:url]) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"Invalid destination.", @"error"),
                                      MP42LocalizedString(@"Can't overwrite the source movie.", @"error message"), 100);
                [_logger writeErrorToLog:*outError];
            }
            return NO;
        }
    }

    if (self.hasFileRepresentation) {
        __block BOOL noErr = YES;

        if (![self.URL isEqualTo:url]) {
            __block _Atomic int32_t done = 0;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);

            NSFileManager *fileManager = [[NSFileManager alloc] init];
            unsigned long long originalFileSize = [[[fileManager attributesOfItemAtPath:self.URL.path error:NULL] valueForKey:NSFileSize] unsignedLongLongValue];

            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                NSError *localError;
                noErr = [fileManager removeItemAtURL:url error:&localError];
                if (!noErr && localError) {
                    [_logger writeErrorToLog:localError];
                }
                noErr = [fileManager copyItemAtURL:self.URL toURL:url error:&localError];
                if (!noErr && localError) {
                    [_logger writeErrorToLog:localError];
                }
                done = 1;
                dispatch_semaphore_signal(sem);
            });

            while (!done) {
                unsigned long long fileSize = [[[fileManager attributesOfItemAtPath:url.path error:NULL] valueForKey:NSFileSize] unsignedLongLongValue];
                [self progressStatus:((double)fileSize / originalFileSize) * 100];
                usleep(450000);
            }
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        }

        if (noErr) {
            self.URL = url;
            success = [self updateMP4FileWithOptions:options error:outError];
        }
        else {
            success = NO;
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be saved.", @"error message"),
                                      MP42LocalizedString(@"You do not have sufficient permissions for this operation.", @"error message"), 101);
                [_logger writeErrorToLog:*outError];
            }
        }
    }
    else {
        self.URL = url;

        NSString *fileExtension = self.URL.pathExtension;
        char *majorBrand = "mp42";
        char *supportedBrands[4];
        uint32_t supportedBrandsCount = 0;
        uint32_t flags = 0;

        if ([options[MP4264BitData] boolValue]) {
            flags += 0x01;
        }

        if ([options[MP4264BitTime] boolValue]) {
            flags += 0x02;
        }

        if ([fileExtension isEqualToString:MP42FileTypeM4V]) {
            majorBrand = "M4V ";
            supportedBrands[0] = majorBrand;
            supportedBrands[1] = "M4A ";
            supportedBrands[2] = "mp42";
            supportedBrands[3] = "isom";
            supportedBrandsCount = 4;
        } else if ([fileExtension isEqualToString:MP42FileTypeM4A] ||
                   [fileExtension isEqualToString:MP42FileTypeM4B] ||
                   [fileExtension isEqualToString:MP42FileTypeM4R]) {
            majorBrand = "M4A ";
            supportedBrands[0] = majorBrand;
            supportedBrands[1] = "mp42";
            supportedBrands[2] = "isom";
            supportedBrandsCount = 3;
        } else {
            supportedBrands[0] = majorBrand;
            supportedBrands[1] = "isom";
            supportedBrandsCount = 2;
        }

        self.fileHandle = MP4CreateEx(self.URL.fileSystemRepresentation,
                                 flags, 1, 1,
                                 majorBrand, 0,
                                 supportedBrands, supportedBrandsCount);
        if (self.fileHandle) {
            MP4SetTimeScale(self.fileHandle, 600);
            [self stopWriting];

            success = [self updateMP4FileWithOptions:options error:outError];
        } else {
            success = NO;
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be saved.", @"error message"),
                                      MP42LocalizedString(@"You do not have sufficient permissions for this operation.", @"error message"), 101);
                [_logger writeErrorToLog:*outError];
            }
        }
    }

    return success;
}

- (BOOL)updateMP4FileWithOptions:(nullable NSDictionary<NSString *, id> *)options error:(NSError * __autoreleasing *)outError {

    // Open the mp4 file
    if (![self startWriting]) {
        if (outError) {
            *outError = MP42Error(MP42LocalizedString(@"The file could not be saved.", @"error message"),
                                  MP42LocalizedString(@"You may do not have sufficient permissions for this operation, or the mp4 file is corrupted.", @"error message"),
                                  101);
            [_logger writeErrorToLog:*outError];
        }
        return NO;
    }

    // Delete tracks
    for (MP42Track *track in _tracksToBeDeleted) {
        [self removeMuxedTrack:track];
    }

    // Init the muxer and prepare the work
    NSMutableArray<MP42Track *> *unsupportedTracks = [[NSMutableArray alloc] init];
#ifdef SB_SANDBOX
    NSMutableArray<MP42SecurityAccessToken *> *importersTokens = [[NSMutableArray alloc] init];
#endif

    self.muxer = [[MP42Muxer alloc] initWithFileHandle:self.fileHandle delegate:self logger:_logger options:options];

    for (MP42Track *track in self.itracks) {
        if (!track.muxed) {
            // Reopen the file importers if they are not already open
            // this happens when the object was unarchived from a file.
            if (![track isMemberOfClass:[MP42ChapterTrack class]]) {
                if (!track.importer && track.URL) {
                    MP42FileImporter *fileImporter = self.importers[track.URL.path];

                    if (!fileImporter) {
#ifdef SB_SANDBOX
                        [importersTokens addObject:[MP42SecurityAccessToken tokenWithObject:track]];
#endif
                        fileImporter = [[MP42FileImporter alloc] initWithURL:track.URL error:outError];
                        if (fileImporter) {
                            self.importers[track.URL.path] = fileImporter;
                        }
                    }

                    if (fileImporter) {
                        track.importer = fileImporter;
                    } else {
                        if (outError) {
                            NSError *error = MP42Error(MP42LocalizedString(@"Missing sources.", @"error message"),
                                                       MP42LocalizedString(@"One or more sources files are missing.", @"error message"), 200);
                            [_logger writeErrorToLog:error];
                            if (outError) { *outError = error; }
                        }

                        break;
                    }
                }

                // Add the track to the muxer
                if (track.importer) {
                    if ([self.muxer canAddTrack:track]) {
                        [self.muxer addTrack:track];
                    } else {
                        // We don't know how to handle this type of track.
                        // Just drop it.
                        NSError *error = MP42Error(MP42LocalizedString(@"Unsupported track", @"error message"),
                                                   [NSString stringWithFormat:@"%@, %u, has not been muxed.", track.name, (unsigned int)track.format],
                                                   201);

                        [_logger writeErrorToLog:error];
                        if (outError) { *outError = error; }

                        [unsupportedTracks addObject:track];
                    }
                }
            }
        }
    }

    [self.muxer setup:outError];
    [self.muxer work];
    self.muxer = nil;

    // Remove the unsupported tracks from the array of the tracks
    // to update. Unsupported tracks haven't been muxed, so there is no
    // need to update them.
    NSMutableArray<MP42Track *> *tracksToUpdate = [self.itracks mutableCopy];
    [tracksToUpdate removeObjectsInArray:unsupportedTracks];

    for (MP42Track *track in self.itracks) {
        track.importer = nil;
    }

    for (MP42FileImporter *importer in self.importers.allValues) {
        for (MP42Track *track in importer.tracks) {
            track.importer = nil;
        }
    }

#ifdef SB_SANDBOX
    [importersTokens removeAllObjects];
#endif
    [self.importers removeAllObjects];

    // Update moov atom
    updateMoovDuration(self.fileHandle);
    updateMajorBrand(self.fileHandle, self.URL);

    // Update modified tracks properties
    for (MP42Track *track in tracksToUpdate) {
        if (track.isEdited) {
            if (![track writeToFile:self.fileHandle error:outError]) {
                if (outError && *outError) {
                    [_logger writeErrorToLog:*outError];
                }
            }
        }
    }

    // Update metadata
    [self.metadata writeMetadataWithFileHandle:self.fileHandle];

    // Close the mp4 file handle
    if (![self stopWriting]) {
        if (outError) {
            *outError = MP42Error(MP42LocalizedString(@"File excedes 4 GB.", @"error message"),
                                  MP42LocalizedString(@"The file is bigger than 4 GB, but it was created with 32bit data chunk offset.\nSelect 64bit data chunk offset in the save panel.", @"error message"),
                                  102);
            [_logger writeErrorToLog:*outError];
        }
        return NO;
    }

    // Generate previews images for chapters
    if ([options[MP42GenerateChaptersPreviewTrack] boolValue] && self.itracks.count) {
        [self createChaptersPreviewAtPosition:[options[MP42ChaptersPreviewPosition] floatValue]];
    } else if ([options[MP42CustomChaptersPreviewTrack] boolValue] && self.itracks.count) {
        [self customChaptersPreview];
    }

    return YES;
}

#pragma mark - Chapters previews

- (BOOL)muxChaptersPreviewTrackId:(MP4TrackId)jpegTrack withChapterTrack:(MP42ChapterTrack *)chapterTrack andRefTrack:(MP42VideoTrack *)videoTrack {
    // Reopen the mp4v2 fileHandle
    if (![self startWriting]) {
        return NO;
    }

    CGFloat maxWidth = 640;
    NSSize imageSize = NSMakeSize(videoTrack.trackWidth, videoTrack.trackHeight);
    if (imageSize.width > maxWidth) {
        imageSize.height = maxWidth / imageSize.width * imageSize.height;
        imageSize.width = maxWidth;
    }
    NSRect rect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);

    if (jpegTrack) {
        MP4DeleteTrack(self.fileHandle, jpegTrack);
    }

    jpegTrack = MP4AddJpegVideoTrack(self.fileHandle, MP4GetTrackTimeScale(self.fileHandle, chapterTrack.trackId),
                                         MP4_INVALID_DURATION, imageSize.width, imageSize.height);

    MP4SetTrackLanguage(self.fileHandle, jpegTrack, [MP42Languages.defaultManager ISO_639_2CodeForExtendedTag:videoTrack.language].UTF8String);
    MP4SetTrackExtendedLanguage(self.fileHandle, jpegTrack, videoTrack.language.UTF8String);
    MP4SetTrackIntegerProperty(self.fileHandle, jpegTrack, "tkhd.layer", 1);
    MP4SetTrackDisabled(self.fileHandle, jpegTrack);

    MP4SampleId samplesCount = MP4GetTrackNumberOfSamples(self.fileHandle, chapterTrack.trackId);
    uint32_t idx = 1;

    for (MP42TextSample *chapterT in chapterTrack.chapters) {
        if (idx > samplesCount) {
            break;
        }

        MP4Duration duration = MP4GetSampleDuration(self.fileHandle, chapterTrack.trackId, idx++);

        NSData *imageData = chapterT.image.data;

        if (!imageData) {
            // Scale the image.
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                               pixelsWide:rect.size.width
                                                                               pixelsHigh:rect.size.height
                                                                            bitsPerSample:8
                                                                          samplesPerPixel:4
                                                                                 hasAlpha:YES
                                                                                 isPlanar:NO
                                                                           colorSpaceName:NSCalibratedRGBColorSpace
                                                                             bitmapFormat:NSBitmapFormatAlphaFirst
                                                                              bytesPerRow:0
                                                                             bitsPerPixel:32];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];

            [[NSColor blackColor] set];
            NSRectFill(rect);

            [chapterT.image.image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];

            [NSGraphicsContext restoreGraphicsState];

            imageData = [bitmap representationUsingType:NSBitmapImageFileTypeJPEG properties:@{}];
        }

        if (imageData.length < UINT32_MAX) {
            MP4WriteSample(self.fileHandle,
                           jpegTrack,
                           imageData.bytes,
                           (uint32_t)imageData.length,
                           duration,
                           0,
                           true);
        }
    }

    MP4RemoveAllTrackReferences(self.fileHandle, "tref.chap", videoTrack.trackId);
    MP4AddTrackReference(self.fileHandle, "tref.chap", chapterTrack.trackId, videoTrack.trackId);
    MP4AddTrackReference(self.fileHandle, "tref.chap", jpegTrack, videoTrack.trackId);
    copyTrackEditLists(self.fileHandle, chapterTrack.trackId, jpegTrack);

    [self stopWriting];

    return YES;
}

- (BOOL)customChaptersPreview {
    MP42ChapterTrack *chapterTrack = nil;
    MP42VideoTrack *refTrack = nil;
    MP4TrackId jpegTrack = 0;

    for (MP42Track *track in self.itracks) {
        if ([track isMemberOfClass:[MP42ChapterTrack class]] && !chapterTrack)
            chapterTrack = (MP42ChapterTrack *)track;

        if ([track isMemberOfClass:[MP42VideoTrack class]] &&
            !(track.format == kMP42VideoCodecType_JPEG)
            && !refTrack)
            refTrack = (MP42VideoTrack *)track;

        if (track.format == kMP42VideoCodecType_JPEG && !jpegTrack)
            jpegTrack = track.trackId;
    }

    if (!refTrack)
        refTrack = [self.itracks objectAtIndex:0];

    [self muxChaptersPreviewTrackId:jpegTrack withChapterTrack:chapterTrack andRefTrack:refTrack];

    return YES;
}

- (BOOL)createChaptersPreviewAtPosition:(CGFloat)position {
    NSInteger decodable = 1;
    MP42ChapterTrack *chapterTrack = nil;
    MP42VideoTrack *refTrack = nil;
    MP4TrackId jpegTrack = 0;

    for (MP42Track *track in self.itracks) {
        if ([track isMemberOfClass:[MP42ChapterTrack class]] && !chapterTrack) {
            chapterTrack = (MP42ChapterTrack *)track;
        }

        if ([track isMemberOfClass:[MP42VideoTrack class]] &&
            !(track.format == kMP42VideoCodecType_JPEG)
            && !refTrack) {
            refTrack = (MP42VideoTrack *)track;
        }

        if ((track.format == kMP42VideoCodecType_JPEG) && !jpegTrack) {
            jpegTrack = track.trackId;
        }

        if (track.format == kMP42VideoCodecType_H264) {
            if ((((MP42VideoTrack *)track).origProfile) == 110) {
                decodable = 0;
            }
        }
    }

    if (!refTrack) {
        refTrack = self.itracks.firstObject;
    }

    if (chapterTrack && decodable && (!jpegTrack)) {
        NSArray<NSImage *> *images = [MP42PreviewGenerator generatePreviewImagesFromChapters:chapterTrack.chapters
                                                                                     fileURL:self.URL
                                                                                  atPosition:position];

        // If we haven't got any images, return.
        if (!images || !images.count) {
            return NO;
        }

        NSArray<MP42TextSample *> *chapters = chapterTrack.chapters;
        [images enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            MP42TextSample *chapter = chapters[idx];
            chapter.image = [[MP42Image alloc] initWithImage:obj];
        }];

        [self muxChaptersPreviewTrackId:jpegTrack withChapterTrack:chapterTrack andRefTrack:refTrack];

        return YES;

    }
    else if (chapterTrack && jpegTrack) {

        // We already have all the tracks, so hook them up.
        if (![self startWriting]) {
            return NO;
        }

        MP4RemoveAllTrackReferences(self.fileHandle, "tref.chap", refTrack.trackId);
        MP4AddTrackReference(self.fileHandle, "tref.chap", chapterTrack.trackId, refTrack.trackId);
        MP4AddTrackReference(self.fileHandle, "tref.chap", jpegTrack, refTrack.trackId);

        [self stopWriting];
    }

    return NO;
}

#pragma mark - Auto Fallback
/**
 * Set automatically a fallback track for AC3 if Stereo track in the same language is present
 */
- (void)setAutoFallback {
    NSMutableArray<MP42AudioTrack *> *availableFallbackTracks = [[NSMutableArray alloc] init];
    NSMutableArray<MP42AudioTrack *> *needFallbackTracks = [[NSMutableArray alloc] init];

    for (MP42AudioTrack *track in [self tracksWithMediaType:kMP42MediaType_Audio] ) {
        if ((track.targetFormat == kMP42AudioCodecType_AC3 ||
             track.targetFormat == kMP42AudioCodecType_EnhancedAC3 ||
             track.targetFormat == kMP42AudioCodecType_DTS) &&
            track.fallbackTrack == nil) {
            [needFallbackTracks addObject:track];
        }
        else if (track.targetFormat == kMP42AudioCodecType_MPEG4AAC ||
                 track.targetFormat == kMP42AudioCodecType_MPEG4AAC_HE) {
            [availableFallbackTracks addObject:track];
        }
    }

    for (MP42AudioTrack *ac3Track in needFallbackTracks) {
        for (MP42AudioTrack *aacTrack in availableFallbackTracks.reverseObjectEnumerator) {
            if ((aacTrack.trackId < ac3Track.trackId) && [aacTrack.language isEqualTo:ac3Track.language]) {
                ac3Track.fallbackTrack = aacTrack;
                break;
            }
        }
    }
}

#pragma mark - NSSecureCoding

#define MP42FILE_VERSION 6

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt:MP42FILE_VERSION forKey:@"MP42FileVersion"];

#ifdef SB_SANDBOX
    NSError *error = nil;
    if (self.URL && self.fileURLBookmark == nil) {
        self.fileURLBookmark = [MP42SecurityAccessToken bookmarkFromURL:self.URL error:&error];
        if (error) {
            [_logger writeErrorToLog:error];
        }
    } else {
        self.fileURLBookmark = nil;
    }

    [coder encodeObject:self.fileURLBookmark forKey:@"bookmark"];
#else
    if (self.URL.isFileReferenceURL) {
        [coder encodeObject:self.URL.filePathURL forKey:@"fileUrl"];
    } else {
        [coder encodeObject:self.URL forKey:@"fileUrl"];
    }
#endif

    [coder encodeObject:_tracksToBeDeleted forKey:@"tracksToBeDeleted"];
    [coder encodeBool:_hasFileRepresentation forKey:@"hasFileRepresentation"];

    [coder encodeObject:self.itracks forKey:@"tracks"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
}

- (id)initWithCoder:(NSCoder *)decoder {
    self = [self init];

    NSInteger version = [decoder decodeIntForKey:@"MP42FileVersion"];

    if (version < MP42FILE_VERSION) {
        return nil;
    }

    _fileURLBookmark = [decoder decodeObjectOfClass:[NSData class] forKey:@"bookmark"];
    if (_fileURLBookmark) {
        BOOL bookmarkDataIsStale;
        NSError *error;
        _URL = [MP42SecurityAccessToken URLFromBookmark:_fileURLBookmark bookmarkDataIsStale:&bookmarkDataIsStale error:&error];

        if (error) {
            [_logger writeErrorToLog:error];
        }

        if (bookmarkDataIsStale) {
            _fileURLBookmark = [MP42SecurityAccessToken bookmarkFromURL:_URL error:&error];
        }
    } else {
        _URL = [decoder decodeObjectOfClass:[NSURL class] forKey:@"fileUrl"];
    }

    _tracksToBeDeleted = [decoder decodeObjectOfClasses:[NSSet setWithObjects:[NSMutableArray class], [MP42Track class], nil]
                                                 forKey:@"tracksToBeDeleted"];

    _hasFileRepresentation = [decoder decodeBoolForKey:@"hasFileRepresentation"];

    _tracks = [decoder decodeObjectOfClasses:[NSSet setWithObjects:[NSMutableArray class], [MP42Track class], nil]
                                      forKey:@"tracks"];
    _metadata = [decoder decodeObjectOfClass:[MP42Metadata class] forKey:@"metadata"];

    return self;
}

- (BOOL)startAccessingSecurityScopedResource {
    return [self.URL startAccessingSecurityScopedResource];
}

- (void)stopAccessingSecurityScopedResource {
    [self.URL stopAccessingSecurityScopedResource];
}

@end
