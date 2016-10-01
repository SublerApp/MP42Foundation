//
//  MP42File.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import "MP42File.h"
#import "MP42FileImporter.h"
#import "MP42Muxer.h"
#import "MP42SubUtilities.h"
#import "MP42PrivateUtilities.h"
#import "MP42Languages.h"
#import "MP42Track+Muxer.h"
#import "MP42Track+Private.h"
#import "MP42PreviewGenerator.h"
#import "MP42Metadata+Private.h"

#import "mp4v2.h"

NSString * const MP4264BitData = @"MP4264BitData";
NSString * const MP4264BitTime = @"MP4264BitTime";
NSString * const MP42GenerateChaptersPreviewTrack = @"MP42ChaptersPreview";
NSString * const MP42CustomChaptersPreviewTrack = @"MP42CustomChaptersPreview";

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
    NSString *output = [NSString stringWithFormat:@"%s: %s\n", level, buffer];

    [_logger writeToLog:output];
}

@interface MP42File () <MP42MuxerDelegate> {
@private
    NSURL           *_fileURL;

    BOOL        _cancelled;

    MP42FileProgressHandler _progressHandler;

    NSMutableArray<__kindof MP42Track *>  *_tracks;
    NSMutableArray<MP42Track *>  *_tracksToBeDeleted;
    MP42Metadata    *_metadata;

    BOOL        _hasFileRepresentation;
}

@property(nonatomic, readwrite)  MP42FileHandle fileHandle;
@property(nonatomic, readwrite, retain) NSURL *URL;

@property(nonatomic, readonly) NSMutableArray<__kindof MP42Track *> *itracks;
@property(nonatomic, readonly) NSMutableDictionary<NSString *, MP42FileImporter *> *importers;

@property(nonatomic, readwrite) MP42Status status;
@property(nonatomic, retain) MP42Muxer *muxer;

@end

@implementation MP42File

@synthesize fileHandle = _fileHandle;
@synthesize URL = _fileURL;

@synthesize itracks = _tracks;
@synthesize importers = _importers;
@synthesize metadata = _metadata;
@synthesize hasFileRepresentation = _hasFileRepresentation;

@synthesize status = _status;
@synthesize progressHandler = _progressHandler;
@synthesize muxer = _muxer;

+ (void)initialize {
    if (self == [MP42File class]) {
        MP4SetLogCallback(logCallback);
        MP4LogSetLevel(MP4_LOG_INFO);
    }
}

+ (void)setGlobalLogger:(id<MP42Logging>)logger
{
    _logger = [logger retain];
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

- (instancetype)initWithURL:(NSURL *)URL error:(NSError * _Nullable *)error {
    self = [super init];
    if (self) {
        _fileURL = [[URL fileReferenceURL] retain];

        // Open the file for reading
        if (![self startReading]) {
            [self release];

            if (error) {
                *error = MP42Error(@"The movie could not be opened.", @"The file is not a mp4 file.", 100);
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
                [self release];

                if (error) {
                    *error = MP42Error(@"Invalid File Type.", @"MOV File cannot be edited.", 100);
                    [_logger writeErrorToLog:*error];
                }

                return nil;
            }
        }

        // Refuse to open fragmented mp4
        if (MP4HaveAtom(_fileHandle, "moof")) {
            [self stopReading];
            [self release];

            if (error) {
                *error = MP42Error(@"Invalid File Type.", @"Fragmented MP4 cannot be edited.", 100);
                [_logger writeErrorToLog:*error];
            }

            return nil;
        };

        // Wraps the tracks in obj-c objects
        _tracks = [[NSMutableArray alloc] init];
        uint32_t tracksCount = MP4GetNumberOfTracks(_fileHandle, 0, 0);
        MP4TrackId chapterId = findChapterTrackId(_fileHandle);
        MP4TrackId previewsId = 0; //findChapterPreviewTrackId(_fileHandle);

        for (int i = 0; i< tracksCount; i++) {
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

            track = [track initWithSourceURL:_fileURL trackID:trackId fileHandle:_fileHandle];
            [_tracks addObject:track];
            [track release];
        }

        // Restore the tracks references in the wrapped tracks
        [self reconnectReferences];

        // Ugly hack to check for the previews track
        for (MP42Track *track in _tracks) {
            if (track.format == kMP42VideoCodecType_JPEG) {
                previewsId = track.trackId;
            }
        }

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
            if (a.fallbackTrackId)
                a.fallbackTrack = [self trackWithTrackID:a.fallbackTrackId];
            if (a.followsTrackId)
                a.followsTrack = [self trackWithTrackID:a.followsTrackId];
        }
        if ([ref isMemberOfClass:[MP42SubtitleTrack class]]) {
            MP42SubtitleTrack *a = (MP42SubtitleTrack *)ref;
            if (a.forcedTrackId)
                a.forcedTrack = [self trackWithTrackID:a.forcedTrackId];
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
            bool isSyncSample;

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

            if ([[self chapters].chapters count] >= currentSampleNum)
                [[self chapters] chapterAtIndex:currentSampleNum - 1].image = frame;

            [frameData release];
            [frame release];
            free(pBytes);
        }
    }
}

#pragma mark - File Inspections

- (NSUInteger)duration {
    NSUInteger duration = 0;
    NSUInteger trackDuration = 0;
    for (MP42Track *track in self.itracks)
        if ((trackDuration = [track duration]) > duration)
            duration = trackDuration;

    return duration;
}

- (uint64_t)dataSize {
    uint64_t estimation = 0;
    for (MP42Track *track in self.itracks)
        estimation += track.dataLength;

    return estimation;
}

- (MP42ChapterTrack *)chapters {
    MP42ChapterTrack *chapterTrack = nil;

    for (MP42Track *track in self.itracks)
        if ([track isMemberOfClass:[MP42ChapterTrack class]])
            chapterTrack = (MP42ChapterTrack *)track;

    return [[chapterTrack retain] autorelease];
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

- (NSArray<MP42Track *> *)tracksWithMediaType:(MP42MediaType)mediaType {
    NSMutableArray<MP42Track *> *tracks = [NSMutableArray array];

    for (MP42Track *track in self.itracks) {
        if (track.mediaType == mediaType)
            [tracks addObject:track];
    }

    return tracks;
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

    if (track.muxer_helper->importer && track.URL) {
        if (self.importers[track.URL.path]) {
            track.muxer_helper->importer = self.importers[track.URL.path];
        } else {
            self.importers[track.URL.path] = track.muxer_helper->importer;
        }
    }

    if ([track isMemberOfClass:[MP42AudioTrack class]]) {
        MP42AudioTrack *audioTrack = (MP42AudioTrack *)track;
        if (![self.itracks containsObject:audioTrack.fallbackTrack]) {
            audioTrack.fallbackTrack = nil;
        }
    }

    if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
        track.duration = self.duration;
    }

    [self.itracks addObject:track];
}

- (void)removeTrackAtIndex:(NSUInteger)index {
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to remove a track while the file is open for writing");
    [self removeTracksAtIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (void)removeTracksAtIndexes:(NSIndexSet *)indexes {
    NSUInteger index = [indexes firstIndex];
    while (index != NSNotFound) {
        MP42Track *track = [self.itracks objectAtIndex:index];

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
        index = [indexes indexGreaterThanIndex:index];
    }

    [self.itracks removeObjectsAtIndexes:indexes];
}

- (void)moveTrackAtIndex:(NSUInteger)index toIndex:(NSUInteger)newIndex {
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to move tracks while the file is open for writing");
    id track = [[self.itracks objectAtIndex:index] retain];

    [self.itracks removeObjectAtIndex:index];
    if (newIndex > [self.itracks count] || newIndex > index) {
        newIndex--;
    }
    [self.itracks insertObject:track atIndex:newIndex];
    [track release];
}

- (void)organizeAlternateGroupsForMediaType:(MP42MediaType)mediaType withGroupID:(NSUInteger)groupID {
    NSArray<MP42Track *> *tracks = [self tracksWithMediaType:mediaType];
    BOOL enabled = NO;

    if (!tracks.count) {
        return;
    }

    for (MP42Track *track in tracks) {
        track.alternate_group = groupID;

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

    MP42MediaType typeToOrganize[] = {kMP42MediaType_Video,
                                      kMP42MediaType_Audio,
                                      kMP42MediaType_Subtitle};

    for (NSUInteger i = 0; i < 3; i++) {
        [self organizeAlternateGroupsForMediaType:typeToOrganize[i]
                                      withGroupID:i];
    }

    for (MP42Track *track in self.itracks) {
        if ([track isMemberOfClass:[MP42ChapterTrack class]])
            track.enabled = NO;
    }
}

#pragma mark - Editing internal

- (void)removeMuxedTrack:(MP42Track *)track {
    if (!self.fileHandle)
        return;

    // We have to handle a few special cases here.
    if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
        MP4ChapterType err = MP4DeleteChapters(self.fileHandle, MP4ChapterTypeAny, track.trackId);
        if (err == 0)
            MP4DeleteTrack(self.fileHandle, track.trackId);
    } else {
        MP4DeleteTrack(self.fileHandle, track.trackId);
    }

    updateTracksCount(self.fileHandle);
    updateMoovDuration(self.fileHandle);
}

#pragma mark - Saving

- (NSURL *)tempURL {
    NSURL *tempURL = nil;
    #ifdef SB_SANDBOX
        NSURL *folderURL = [fileURL URLByDeletingLastPathComponent];
        tempURL = [fileManager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:folderURL create:YES error:&error];
    #else
        tempURL = [self.URL URLByDeletingLastPathComponent];
    #endif

    if (tempURL) {
        tempURL = [tempURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.tmp", self.URL.lastPathComponent]];
    }

    return tempURL;
}

- (BOOL)optimize {
    __block BOOL noErr = NO;
    __block int32_t done = 0;

    @autoreleasepool {
        NSError *error = nil;
        NSURL *tempURL = [self tempURL];
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        if (tempURL) {
            unsigned long long originalFileSize = [[[fileManager attributesOfItemAtPath:self.URL.path error:nil] valueForKey:NSFileSize] unsignedLongLongValue];

            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                noErr = MP4Optimize(self.URL.fileSystemRepresentation, tempURL.fileSystemRepresentation);
                OSAtomicIncrement32Barrier(&done);
                dispatch_semaphore_signal(sem);
            });

            // Loop to check the progress
            while (!done) {
                unsigned long long fileSize = [[[fileManager attributesOfItemAtPath:tempURL.path error:nil] valueForKey:NSFileSize] unsignedLongLongValue];
                [self progressStatus:((double)fileSize / originalFileSize) * 100];
                usleep(450000);
            }

            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

            // Additional check to see if we can open the optimized file
            if (noErr && [[[MP42File alloc] initWithURL:tempURL error:NULL] autorelease]) {
                // Replace the original file
                NSURL *result = nil;
                noErr = [fileManager replaceItemAtURL:self.URL
                                        withItemAtURL:tempURL
                                       backupItemName:nil
                                              options:NSFileManagerItemReplacementWithoutDeletingBackupItem
                                     resultingItemURL:&result error:&error];
                if (noErr) {
                    self.URL = result;
                } else {
                    [_logger writeErrorToLog:error];
                }
            }

            if (!noErr) {
                // Remove the temp file if the optimization didn't complete
                [fileManager removeItemAtURL:tempURL error:NULL];
            }
        }

        dispatch_release(sem);
        [fileManager release];
    }

    return noErr;
}

- (void)cancel {
    _cancelled = YES;
    [self.muxer cancel];
}

- (void)progressStatus:(double)progress {
    if (_progressHandler) {
        _progressHandler(progress);
    }
}

- (BOOL)writeToUrl:(NSURL *)url options:(nullable NSDictionary<NSString *, id> *)options error:(NSError **)outError {
    BOOL success = YES;

    if (!url) {
        if (outError) {
            *outError = MP42Error(@"Invalid path.", @"The destination path cannot be empty.", 100);
            [_logger writeErrorToLog:*outError];
        }
        return NO;
    }

    for (MP42Track *track in self.tracks) {
        NSURL *sourceURL = track.URL.filePathURL;
        if ([sourceURL isEqualTo:url]) {
            if (outError) {
                *outError = MP42Error(@"Invalid destination.", @"Can't overwrite the source movie.", 100);
                [_logger writeErrorToLog:*outError];
            }
            return NO;
        }
    }

    if (self.hasFileRepresentation) {
        __block BOOL noErr = YES;

        if (![self.URL isEqualTo:url]) {
            __block int32_t done = 0;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);

            NSFileManager *fileManager = [[NSFileManager alloc] init];
            unsigned long long originalFileSize = [[[fileManager attributesOfItemAtPath:self.URL.path error:NULL] valueForKey:NSFileSize] unsignedLongLongValue];

            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                noErr = [fileManager copyItemAtURL:self.URL toURL:url error:outError];
                if (!noErr && *outError) {
                    [*outError retain];
                }
                OSAtomicIncrement32Barrier(&done);
                dispatch_semaphore_signal(sem);
            });

            while (!done) {
                unsigned long long fileSize = [[[fileManager attributesOfItemAtPath:url.path error:NULL] valueForKey:NSFileSize] unsignedLongLongValue];
                [self progressStatus:((double)fileSize / originalFileSize) * 100];
                usleep(450000);
            }
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            dispatch_release(sem);
            [fileManager release];
        }

        if (noErr) {
            self.URL = url;
            success = [self updateMP4FileWithOptions:options error:outError];
        }
        else {
            success = NO;
            [*outError autorelease];
        }
    }
    else {
        self.URL = url;

        NSString *fileExtension = self.URL.pathExtension;
        char *majorBrand = "mp42";
        char *supportedBrands[4];
        uint32_t supportedBrandsCount = 0;
        uint32_t flags = 0;

        if ([options[MP4264BitData] boolValue])
            flags += 0x01;

        if ([options[MP4264BitTime] boolValue])
            flags += 0x02;

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
                *outError = MP42Error(@"The file could not be saved.", @"You do not have sufficient permissions for this operation.", 101);
                [_logger writeErrorToLog:*outError];
            }
        }
    }

    return success;
}

- (BOOL)updateMP4FileWithOptions:(nullable NSDictionary<NSString *, id> *)options error:(NSError **)outError {

    // Open the mp4 file
    if (![self startWriting]) {
        if (outError) {
            *outError = MP42Error(@"The file could not be saved.", @"You may do not have sufficient permissions for this operation, or the mp4 file is corrupted.", 101);
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
    self.muxer = [[[MP42Muxer alloc] initWithFileHandle:self.fileHandle delegate:self logger:_logger] autorelease];

    for (MP42Track *track in self.itracks) {
        if (!track.muxed) {
            // Reopen the file importer is they are not already open
            // this happens when the object was unarchived from a file.
            if (![track isMemberOfClass:[MP42ChapterTrack class]]) {
                if (!track.muxer_helper->importer && track.URL) {
                    MP42FileImporter *fileImporter = [self.importers valueForKey:track.URL.path];

                    if (!fileImporter) {
                        fileImporter = [[[MP42FileImporter alloc] initWithURL:track.URL error:outError] autorelease];
                        if (fileImporter) {
                            self.importers[track.URL.path] = fileImporter;
                        }
                    }

                    if (fileImporter) {
                        track.muxer_helper->importer = fileImporter;
                    } else {
                        if (outError) {
                            NSError *error = MP42Error(@"Missing sources.", @"One or more sources files are missing.", 200);
                            [_logger writeErrorToLog:error];
                            if (outError) { *outError = error; }
                        }

                        break;
                    }
                }

                // Add the track to the muxer
                if (track.muxer_helper->importer) {
                    if ([self.muxer canAddTrack:track]) {
                        [self.muxer addTrack:track];
                    } else {
                        // We don't know how to handle this type of track.
                        // Just drop it.
                        NSError *error = MP42Error(@"Unsupported track",
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
    // to update them.
    NSMutableArray<MP42Track *> *tracksToUpdate = [self.itracks mutableCopy];
    [tracksToUpdate removeObjectsInArray:unsupportedTracks];
    [unsupportedTracks release];

    [self.importers removeAllObjects];

    // Update modified tracks properties
    updateMoovDuration(self.fileHandle);
    for (MP42Track *track in tracksToUpdate) {
        if (track.isEdited) {
            if (![track writeToFile:self.fileHandle error:outError]) {
                if (outError && *outError) {
                    [_logger writeErrorToLog:*outError];
                }
            }
        }
    }

    [tracksToUpdate release];

    // Update metadata
    if (self.metadata.isEdited) {
        [self.metadata writeMetadataWithFileHandle:self.fileHandle];
    }

    // Close the mp4 file handle
    if (![self stopWriting]) {
        if (outError) {
            *outError = MP42Error(@"File excedes 4 GB.",
                                  @"The file is bigger than 4 GB, but it was created with 32bit data chunk offset.\nSelect 64bit data chunk offset in the save panel.",
                                  102);
            [_logger writeErrorToLog:*outError];
        }
        return NO;
    }

    // Generate previews images for chapters
    if ([options[MP42GenerateChaptersPreviewTrack] boolValue] && self.itracks.count) {
        [self createChaptersPreview];
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

    MP4SetTrackLanguage(self.fileHandle, jpegTrack, lang_for_english([videoTrack.language UTF8String])->iso639_2);
    MP4SetTrackIntegerProperty(self.fileHandle, jpegTrack, "tkhd.layer", 1);
    MP4SetTrackDisabled(self.fileHandle, jpegTrack);

    NSUInteger idx = 1;

    for (MP42TextSample *chapterT in chapterTrack.chapters) {
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
                                                                             bitmapFormat:NSAlphaFirstBitmapFormat
                                                                              bytesPerRow:0
                                                                             bitsPerPixel:32];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];

            [[NSColor blackColor] set];
            NSRectFill(rect);

            if (chapterT.image.image)
                [[chapterT image].image drawInRect:rect fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];

            [NSGraphicsContext restoreGraphicsState];

            imageData = [bitmap representationUsingType:NSJPEGFileType properties:@{}];
            [bitmap release];
        }

        MP4WriteSample(self.fileHandle,
                       jpegTrack,
                       [imageData bytes],
                       [imageData length],
                       duration,
                       0,
                       true);
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

- (BOOL)createChaptersPreview {
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
        NSArray<NSImage *> *images = [MP42PreviewGenerator generatePreviewImagesFromChapters:chapterTrack.chapters fileURL:self.URL];

        // If we haven't got any images, return.
        if (!images || !images.count) {
            return NO;
        }

        NSArray<MP42TextSample *> *chapters = chapterTrack.chapters;
        [images enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            MP42TextSample *chapter = chapters[idx];
            chapter.image = [[[MP42Image alloc] initWithImage:obj] autorelease];
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
            track.targetFormat == kMP42AudioCodecType_EnhancedAC3) &&
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

    [availableFallbackTracks release];
    [needFallbackTracks release];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt:4 forKey:@"MP42FileVersion"];

#ifdef SB_SANDBOX
    if ([fileURL respondsToSelector:@selector(startAccessingSecurityScopedResource)]) {
            NSData *bookmarkData = nil;
            NSError *error = nil;
            bookmarkData = [fileURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                             includingResourceValuesForKeys:nil
                                              relativeToURL:nil // Make it app-scoped
                                                      error:&error];
        if (error) {
            NSLog(@"Error creating bookmark for URL (%@): %@", fileURL, error);
        }
        
        [coder encodeObject:bookmarkData forKey:@"bookmark"];

    } else {
        [coder encodeObject:fileURL forKey:@"fileUrl"];
    }
#else
    if ([self.URL isFileReferenceURL]) {
        [coder encodeObject:[self.URL filePathURL] forKey:@"fileUrl"];
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
    self = [super init];

    NSData *bookmarkData = [decoder decodeObjectOfClass:[NSData class] forKey:@"bookmark"];
    if (bookmarkData) {
        BOOL bookmarkDataIsStale;
        NSError *error;
        _fileURL = [[NSURL
                    URLByResolvingBookmarkData:bookmarkData
                    options:NSURLBookmarkResolutionWithSecurityScope
                    relativeToURL:nil
                    bookmarkDataIsStale:&bookmarkDataIsStale
                    error:&error] retain];
    } else {
        _fileURL = [[decoder decodeObjectOfClass:[NSURL class] forKey:@"fileUrl"] retain];
    }

    _tracksToBeDeleted = [[decoder decodeObjectOfClass:[NSMutableArray class] forKey:@"tracksToBeDeleted"] retain];

    _hasFileRepresentation = [decoder decodeBoolForKey:@"hasFileRepresentation"];

    _tracks = [[decoder decodeObjectOfClass:[NSMutableArray class] forKey:@"tracks"] retain];
    _metadata = [[decoder decodeObjectOfClass:[MP42Metadata class] forKey:@"metadata"] retain];

    return self;
}

- (void)dealloc {
    [_progressHandler release];
    [_fileURL release];
    [_tracks release];
    [_importers release];
    [_tracksToBeDeleted release];
    [_metadata release];
    [_muxer release];

    [super dealloc];
}

@end
