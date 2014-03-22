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
#import "MP42PreviewGenerator.h"

#import "mp4v2.h"

NSString * const MP4264BitData = @"MP4264BitData";
NSString * const MP4264BitTime = @"MP4264BitTime";
NSString * const MP42GenerateChaptersPreviewTrack = @"MP42ChaptersPreview";
NSString * const MP42CustomChaptersPreviewTrack = @"MP42CustomChaptersPreview";
NSString * const MP42OrganizeAlternateGroups = @"MP42AlternateGroups";

static void logCallback(MP4LogLevel loglevel, const char* fmt, va_list ap)
{
    const char *level;

    if ([[NSUserDefaults standardUserDefaults] valueForKey:@"Debug"]) {
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
        printf("%s: ", level);
        vprintf(fmt, ap);
        printf("\n");
    }
}

@interface MP42File () <MP42MuxerDelegate>

@property(nonatomic, readwrite)  MP42FileHandle fileHandle;
@property(nonatomic, readwrite, retain) NSURL *URL;

@property(nonatomic, readonly) NSMutableArray *itracks;
@property(nonatomic, readonly) NSMutableDictionary *importers;

@property(nonatomic, readwrite) MP42Status status;
@property(nonatomic, retain) MP42Muxer *muxer;

- (void)reconnectReferences;

- (void)removeMuxedTrack:(MP42Track *)track;
- (void)organizeAlternateGroupsForMediaType:(NSString *)mediaType withGroupID:(NSUInteger)groupID;

- (BOOL)createChaptersPreview;

@end

@implementation MP42File

@synthesize fileHandle = _fileHandle;
@synthesize delegate = _delegate;
@synthesize URL = _fileURL;

@synthesize itracks = _tracks;
@synthesize importers = _importers;
@synthesize metadata = _metadata;
@synthesize hasFileRepresentation = _hasFileRepresentation;

@synthesize status = _status;
@synthesize muxer = _muxer;

+ (void)initialize
{
    MP4SetLogCallback(logCallback);
    MP4LogSetLevel(MP4_LOG_ERROR);
}

- (BOOL)startReading {
    NSAssert(self.fileHandle == MP4_INVALID_FILE_HANDLE, @"File Handle already open");
    _fileHandle = MP4Read([[self.URL path] fileSystemRepresentation]);

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
    _fileHandle = MP4Modify([[self.URL path] fileSystemRepresentation], 0);

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

- (id)init
{
    if ((self = [super init])) {
        _hasFileRepresentation = NO;
        _tracks = [[NSMutableArray alloc] init];
        _tracksToBeDeleted = [[NSMutableArray alloc] init];

        _metadata = [[MP42Metadata alloc] init];
        _importers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (instancetype)initWithDelegate:(id <MP42FileDelegate>)del
{
    if ((self = [self init])) {
        _delegate = del;
    }

    return self;
}

- (instancetype)initWithExistingFile:(NSURL *)URL andDelegate:(id <MP42FileDelegate>)del
{
    if ((self = [super init]))
	{
        _delegate = del;
        _fileURL = [[URL fileReferenceURL] retain];
        _hasFileRepresentation = YES;

        if (![self startReading]) {
            [self release];
			return nil;
        }

        const char *brand = NULL;
        MP4GetStringProperty(_fileHandle, "ftyp.majorBrand", &brand);
        if (brand != NULL) {
            if (!strcmp(brand, "qt  ")) {
                [self stopReading];
                [self release];
                return nil;
            }
        }

        _tracks = [[NSMutableArray alloc] init];
        uint32_t tracksCount = MP4GetNumberOfTracks(_fileHandle, 0, 0);
        MP4TrackId chapterId = findChapterTrackId(_fileHandle);
        MP4TrackId previewsId = 0; //findChapterPreviewTrackId(_fileHandle);

        for (int i = 0; i< tracksCount; i++) {
            id track;
            MP4TrackId trackId = MP4FindTrackId(_fileHandle, i, 0, 0);
            const char* type = MP4GetTrackType(_fileHandle, trackId);

            if (MP4_IS_AUDIO_TRACK_TYPE(type))
                track = [MP42AudioTrack alloc];
            else if (MP4_IS_VIDEO_TRACK_TYPE(type))
                track = [MP42VideoTrack alloc];
            else if (!strcmp(type, MP4_TEXT_TRACK_TYPE)) {
                if (trackId == chapterId)
                    track = [MP42ChapterTrack alloc];
                else
                    track = [MP42Track alloc];
            }
            else if (!strcmp(type, MP4_SUBTITLE_TRACK_TYPE))
                track = [MP42SubtitleTrack alloc];
            else if (!strcmp(type, MP4_SUBPIC_TRACK_TYPE))
                track = [MP42SubtitleTrack alloc];
            else if (!strcmp(type, MP4_CC_TRACK_TYPE))
                track = [MP42ClosedCaptionTrack alloc];
            else
                track = [MP42Track alloc];

            track = [track initWithSourceURL:_fileURL trackID:trackId fileHandle:_fileHandle];
            [_tracks addObject:track];
            [track release];
        }

        [self reconnectReferences];

        for (MP42Track *track in _tracks)
            if ([track.format isEqualToString:MP42VideoFormatJPEG])
                previewsId = track.Id;

        [self loadPreviewsFromTrackID:previewsId];

        _tracksToBeDeleted = [[NSMutableArray alloc] init];
        _metadata = [[MP42Metadata alloc] initWithSourceURL:_fileURL fileHandle:_fileHandle];
        _importers = [[NSMutableDictionary alloc] init];

        [self stopReading];
	}

	return self;
}

- (void)reconnectReferences
{
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

- (void)loadPreviewsFromTrackID:(MP4TrackId) trackID
{
    MP42Track *track = [self trackWithTrackID:trackID];
    if (track) {
        MP4SampleId sampleNum = MP4GetTrackNumberOfSamples(self.fileHandle, track.Id);

        for (MP4SampleId currentSampleNum = 1; currentSampleNum <= sampleNum; currentSampleNum++) {
            uint8_t *pBytes = NULL;
            uint32_t numBytes = 0;
            MP4Duration duration;
            MP4Duration renderingOffset;
            MP4Timestamp pStartTime;
            bool isSyncSample;

            if (!MP4ReadSample(self.fileHandle,
                               track.Id,
                               currentSampleNum,
                               &pBytes, &numBytes,
                               &pStartTime, &duration, &renderingOffset,
                               &isSyncSample)) {
                break;
            }

            NSData *frameData = [[NSData alloc] initWithBytes:pBytes length:numBytes];
            MP42Image *frame = [[MP42Image alloc] initWithData:frameData type:MP42_ART_JPEG];

            [[self chapters] chapterAtIndex:currentSampleNum - 1].image = frame;

            [frameData release];
            [frame release];
            free(pBytes);
        }
    }
}

#pragma mark - File Inspections

- (NSUInteger)duration
{
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

- (MP42ChapterTrack *)chapters
{
    MP42ChapterTrack *chapterTrack = nil;

    for (MP42Track *track in self.itracks)
        if ([track isMemberOfClass:[MP42ChapterTrack class]])
            chapterTrack = (MP42ChapterTrack *) track;

    return [[chapterTrack retain] autorelease];
}

- (NSArray *)tracks {
    return [NSArray arrayWithArray:self.itracks];
}

- (NSUInteger)tracksCount
{
    return [self.itracks count];
}

- (id)trackAtIndex:(NSUInteger)index
{
    return [self.itracks objectAtIndex:index];
}

- (id)trackWithTrackID:(NSUInteger)trackId
{
    for (MP42Track *track in self.itracks) {
        if (track.Id == trackId)
            return track;
    }

    return nil;
}

- (NSArray *)tracksWithMediaType:(NSString *)mediaType
{
    NSMutableArray *tracks = [NSMutableArray array];

    for (MP42Track *track in self.itracks) {
        if ([track.mediaType isEqualToString:mediaType])
            [tracks addObject:track];
    }

    return tracks;
}

#pragma mark - Editing

- (void)addTrack:(MP42Track *)track
{
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to add a track while the file is open for writing");
    track.sourceId = track.Id;
    track.Id = 0;
    track.muxed = NO;
    track.isEdited = YES;

    track.language = track.language;
    track.name = track.name;
    if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
        for (id previousTrack in self.itracks)
            if ([previousTrack isMemberOfClass:[MP42ChapterTrack class]]) {
                [self.itracks removeObject:previousTrack];
                break;
        }
    }

    if (trackNeedConversion(track.format) || track.needConversion) {
        track.needConversion = YES;
        track.sourceFormat = track.format;
        if ([track isMemberOfClass:[MP42AudioTrack class]]) {
            MP42AudioTrack *audioTrack = (MP42AudioTrack *)track;
            track.format = MP42AudioFormatAAC;
            audioTrack.sourceChannels = audioTrack.channels;
            if ([audioTrack.mixdownType isEqualToString:SBMonoMixdown] || audioTrack.sourceChannels == 1)
                audioTrack.channels = 1;
            else if (audioTrack.mixdownType)
                audioTrack.channels = 2;
        }
        else if ([track isMemberOfClass:[MP42SubtitleTrack class]])
            track.format = MP42SubtitleFormatTx3g;
    }

    if (track.muxer_helper->importer && track.sourceURL) {
        if ([self.importers objectForKey:[[track sourceURL] path]])
            track.muxer_helper->importer = [_importers objectForKey:[[track sourceURL] path]];
        else
            [self.importers setObject:track.muxer_helper->importer forKey:[[track sourceURL] path]];
    }

    [self.itracks addObject:track];
}

- (void)removeTrackAtIndex:(NSUInteger) index
{
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to remove a track while the file is open for writing");
    [self removeTracksAtIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (void)removeTracksAtIndexes:(NSIndexSet *)indexes
{
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

- (void)moveTrackAtIndex:(NSUInteger)index toIndex:(NSUInteger) newIndex
{
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to move tracks while the file is open for writing");
    id track = [[self.itracks objectAtIndex:index] retain];

    [self.itracks removeObjectAtIndex:index];
    if (newIndex > [self.itracks count] || newIndex > index)
        newIndex--;
    [self.itracks insertObject:track atIndex:newIndex];
    [track release];
}

- (void)organizeAlternateGroupsForMediaType:(NSString *)mediaType withGroupID:(NSUInteger)groupID
{
    NSArray *tracks = [self tracksWithMediaType:mediaType];
    BOOL enabled = NO;

    if (![tracks count])
        return;

    for (MP42Track *track in tracks) {
        track.alternate_group = groupID;

        if (track.enabled && !enabled) {
            enabled = YES;
        } else if (track.enabled) {
            track.enabled = NO;
        }
    }

    if (!enabled)
        [[tracks objectAtIndex:0] setEnabled:YES];
}

- (void)organizeAlternateGroups
{
    NSAssert(self.status != MP42StatusWriting, @"Unsupported operation: trying to organize alternate groups while the file is open for writing");

    NSArray *typeToOrganize = @[MP42MediaTypeVideo,
                                MP42MediaTypeAudio,
                                MP42MediaTypeSubtitle];

    for (int i = 0; i < [typeToOrganize count]; i++) {
        [self organizeAlternateGroupsForMediaType:[typeToOrganize objectAtIndex:i]
                                      withGroupID:i];
    }

    for (MP42Track *track in self.itracks) {
        if ([track isMemberOfClass:[MP42ChapterTrack class]])
            track.enabled = NO;
    }
}

#pragma mark - Editing internal

- (void)removeMuxedTrack:(MP42Track *)track
{
    if (!self.fileHandle)
        return;

    // We have to handle a few special cases here.
    if ([track isMemberOfClass:[MP42ChapterTrack class]]) {
        MP4ChapterType err = MP4DeleteChapters(self.fileHandle, MP4ChapterTypeAny, track.Id);
        if (err == 0)
            MP4DeleteTrack(self.fileHandle, track.Id);
    }
    else
        MP4DeleteTrack(self.fileHandle, track.Id);

    updateTracksCount(self.fileHandle);
    updateMoovDuration(self.fileHandle);
}

#pragma mark - Saving

- (BOOL)optimize
{
    __block BOOL noErr = NO;
    __block BOOL done = NO;

    @autoreleasepool {
        NSError *error;

        NSFileManager *fileManager = [[NSFileManager alloc] init];
#ifdef SB_SANDBOX
        NSURL *folderURL = [fileURL URLByDeletingLastPathComponent];
        NSURL *tempURL = [fileManager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:folderURL create:YES error:&error];
#else
        NSURL *tempURL = [self.URL URLByDeletingLastPathComponent];
#endif
        if (tempURL) {
            tempURL = [tempURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.tmp", [self.URL lastPathComponent]]];

            unsigned long long originalFileSize = [[[fileManager attributesOfItemAtPath:[self.URL path] error:nil] valueForKey:NSFileSize] unsignedLongLongValue];

            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                noErr = MP4Optimize([[self.URL path] fileSystemRepresentation], [[tempURL path] fileSystemRepresentation]);
                done = YES;
            });

            // Loop to check the progress
            while (!done) {
                unsigned long long fileSize = [[[fileManager attributesOfItemAtPath:[tempURL path] error:nil] valueForKey:NSFileSize] unsignedLongLongValue];
                [self progressStatus:((CGFloat)fileSize / originalFileSize) * 100];
                usleep(450000);
            }

            if (noErr) {
                // Additional check to see if we can open the optimized file
                MP42File *optimizedFile = [[MP42File alloc] initWithExistingFile:tempURL andDelegate:nil];
                if (!optimizedFile) {
                    // If not, return no
                    noErr = NO;
                    [optimizedFile release];
                } else {
                    // Else replace the original file
                    [optimizedFile release];
                    NSURL *result = nil;
                    noErr = [fileManager replaceItemAtURL:self.URL withItemAtURL:tempURL backupItemName:nil options:0 resultingItemURL:&result error:&error];
                    if (noErr) {
                        self.URL = result;
                    }
                }
            } else {
                // Remove the temp file if the optimization didn't complete
                [fileManager removeItemAtPath:[tempURL path] error:NULL];
            }
        }

        [fileManager release];
    }

    if ([self.delegate respondsToSelector:@selector(saveDidEnd:)])
        [self.delegate performSelector:@selector(saveDidEnd:) withObject:self];

    return noErr;
}

- (void)cancel;
{
    _cancelled = YES;
    [self.muxer cancel];
}

- (void)progressStatus:(CGFloat)progress {
    if ([_delegate respondsToSelector:@selector(progressStatus:)])
        [_delegate progressStatus:progress];
}

- (BOOL)writeToUrl:(NSURL *)url withAttributes:(NSDictionary *)attributes error:(NSError **)outError
{
    BOOL success = YES;

    if (!url) {
        if (outError) {
            *outError = MP42Error(@"Invalid path.", @"The destination path cannot be empty.", 100);
        }
        return NO;
    }

    if ([self hasFileRepresentation]) {
        __block BOOL noErr = YES;

        if (![self.URL isEqualTo:url]) {
            __block BOOL done = NO;
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            unsigned long long originalFileSize = [[[fileManager attributesOfItemAtPath:[self.URL path] error:NULL] valueForKey:NSFileSize] unsignedLongLongValue];

            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                noErr = [fileManager copyItemAtURL:self.URL toURL:url error:outError];
                if (!noErr && *outError) {
                    [*outError retain];
                }
                done = YES;
            });

            while (!done) {
                unsigned long long fileSize = [[[fileManager attributesOfItemAtPath:[url path] error:NULL] valueForKey:NSFileSize] unsignedLongLongValue];
                [self progressStatus:((CGFloat)fileSize / originalFileSize) * 100];
                usleep(450000);
            }
            [fileManager release];
        }

        if (noErr) {
            self.URL = url;
            success = [self updateMP4FileWithAttributes:attributes error:outError];
        } else {
            success = NO;
            [*outError autorelease];
        }
    }
    else {
        self.URL = url;

        NSString *fileExtension = [self.URL pathExtension];
        char *majorBrand = "mp42";
        char *supportedBrands[4];
        uint32_t supportedBrandsCount = 0;
        uint32_t flags = 0;

        if ([[attributes valueForKey:MP4264BitData] boolValue])
            flags += 0x01;

        if ([[attributes valueForKey:MP4264BitTime] boolValue])
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

        self.fileHandle = MP4CreateEx([[self.URL path] fileSystemRepresentation],
                                 flags, 1, 1,
                                 majorBrand, 0,
                                 supportedBrands, supportedBrandsCount);
        if (self.fileHandle) {
            MP4SetTimeScale(self.fileHandle, 600);
            [self stopWriting];

            success = [self updateMP4FileWithAttributes:attributes error:outError];
        }
    }

    return success;
}

- (BOOL)updateMP4FileWithAttributes:(NSDictionary *)attributes error:(NSError **)outError
{
    BOOL noErr = YES;

    // Organize the alternate groups
    if ([[attributes valueForKey:MP42OrganizeAlternateGroups] boolValue])
        [self organizeAlternateGroups];

    // Open the mp4 file
    if (![self startWriting]) {
        if (outError)
            *outError = MP42Error(@"Unable to open the file", nil, 100);
        return NO;
    }

    // Delete tracks
    for (MP42Track *track in _tracksToBeDeleted)
        [self removeMuxedTrack:track];

    // Init the muxer and prepare the work
    NSMutableArray *tracksToMux = [[NSMutableArray alloc] init];

    for (MP42Track *track in self.itracks) {
        if (!track.muxed) {
            // Reopen the file importer is they are not already open
            // this happens when the object was unarchived from a file
            if (![track isMemberOfClass:[MP42ChapterTrack class]] && !track.muxer_helper->importer && [track sourceURL]) {
                MP42FileImporter *fileImporter = [self.importers valueForKey:[[track sourceURL] path]];

                if (!fileImporter) {
                    fileImporter = [[[MP42FileImporter alloc] initWithURL:[track sourceURL] error:outError] autorelease];
                    [self.importers setObject:fileImporter forKey:[[track sourceURL] path]];
                }

                if (fileImporter) {
                    track.muxer_helper->importer = fileImporter;
                } else {
                    *outError = MP42Error(@"Missing sources.",
                                          @"One or more sources files are missing.",
                                          200);
                    noErr = NO;
                    break;
                }

            }

            // Add the track to the muxer
            if (track.muxer_helper->importer)
                [tracksToMux addObject:track];
        }
    }

    if (!noErr) {
        [self stopWriting];
        return NO;
    }

    if ([tracksToMux count]) {
        self.muxer = [[[MP42Muxer alloc] initWithDelegate:self] autorelease];

        for (MP42Track *track in tracksToMux) {
            [self.muxer addTrack:track];
        }

        // Setup the muxer
        noErr = [self.muxer setup:self.fileHandle error:outError];

        if (!noErr) {
            self.muxer = nil;
            [self stopWriting];
            return NO;
        }

        // Start the muxer and wait
        [self.muxer work];
        self.muxer = nil;
    }

    [tracksToMux release];
    [self.importers removeAllObjects];

    // Update modified tracks properties
    updateMoovDuration(self.fileHandle);
    for (MP42Track *track in self.itracks) {
        if (track.isEdited) {
            noErr = [track writeToFile:self.fileHandle error:outError];
            if (!noErr)
                break;
        }
    }

    // Update metadata
    if (self.metadata.isEdited)
        [self.metadata writeMetadataWithFileHandle:self.fileHandle];

    // Close the mp4 file handle
    if (![self stopWriting]) {
        if (outError)
            *outError = MP42Error(@"File excedes 4 GB.",
                                  @"The file is bigger than 4 GB, but it was created with 32bit data chunk offset.\nSelect 64bit data chunk offset in the save panel.",
                                  100);
        return NO;
    }

    // Generate previews images for chapters
    if ([[attributes valueForKey:MP42GenerateChaptersPreviewTrack] boolValue] && [self.itracks count]) {
        [self createChaptersPreview];
    } else if ([[attributes valueForKey:MP42CustomChaptersPreviewTrack] boolValue] && [self.itracks count]) {
        [self customChaptersPreview];
    }

    if ([self.delegate respondsToSelector:@selector(saveDidEnd:)])
        [self.delegate performSelector:@selector(saveDidEnd:) withObject:self];

    return noErr;
}

#pragma mark - Chapters previews

- (BOOL)muxChaptersPreviewTrackId:(MP4TrackId)jpegTrack withChapterTrack:(MP42ChapterTrack *)chapterTrack andRefTrack:(MP42VideoTrack *)videoTrack {
    // Reopen the mp4v2 fileHandle
    if (![self startWriting])
        return NO;

    CGFloat maxWidth = 640;
    NSSize imageSize = NSMakeSize(videoTrack.trackWidth, videoTrack.trackHeight);
    if (imageSize.width > maxWidth) {
        imageSize.height = maxWidth / imageSize.width * imageSize.height;
        imageSize.width = maxWidth;
    }
    NSRect rect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);

    if (jpegTrack ) {
        MP4DeleteTrack(self.fileHandle, jpegTrack);
    }

    jpegTrack = MP4AddJpegVideoTrack(self.fileHandle, MP4GetTrackTimeScale(self.fileHandle, [chapterTrack Id]),
                                         MP4_INVALID_DURATION, imageSize.width, imageSize.height);

    MP4SetTrackLanguage(self.fileHandle, jpegTrack, lang_for_english([videoTrack.language UTF8String])->iso639_2);
    MP4SetTrackIntegerProperty(self.fileHandle, jpegTrack, "tkhd.layer", 1);
    MP4SetTrackDisabled(self.fileHandle, jpegTrack);

    NSUInteger idx = 1;

    for (MP42TextSample *chapterT in [chapterTrack chapters]) {
        MP4Duration duration = MP4GetSampleDuration(self.fileHandle, chapterTrack.Id, idx++);

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

            imageData = [bitmap representationUsingType:NSJPEGFileType properties:nil];
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

    MP4RemoveAllTrackReferences(self.fileHandle, "tref.chap", videoTrack.Id);
    MP4AddTrackReference(self.fileHandle, "tref.chap", chapterTrack.Id, videoTrack.Id);
    MP4AddTrackReference(self.fileHandle, "tref.chap", jpegTrack, videoTrack.Id);
    copyTrackEditLists(self.fileHandle, chapterTrack.Id, jpegTrack);

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
            ![track.format isEqualToString:MP42VideoFormatJPEG]
            && !refTrack)
            refTrack = (MP42VideoTrack *)track;

        if ([track.format isEqualToString:MP42VideoFormatJPEG] && !jpegTrack)
            jpegTrack = track.Id;
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
        if ([track isMemberOfClass:[MP42ChapterTrack class]] && !chapterTrack)
            chapterTrack = (MP42ChapterTrack *)track;

        if ([track isMemberOfClass:[MP42VideoTrack class]] &&
            ![track.format isEqualToString:MP42VideoFormatJPEG]
            && !refTrack)
            refTrack = (MP42VideoTrack *)track;

        if ([track.format isEqualToString:MP42VideoFormatJPEG] && !jpegTrack)
            jpegTrack = track.Id;

        if ([track.format isEqualToString:MP42VideoFormatH264])
            if ((((MP42VideoTrack *)track).origProfile) == 110)
                decodable = 0;
    }

    if (!refTrack)
        refTrack = [self.itracks objectAtIndex:0];

    if (chapterTrack && !jpegTrack && decodable) {
        @autoreleasepool {
            NSArray *images = [MP42PreviewGenerator generatePreviewImagesFromChapters:[chapterTrack chapters] andFile:self.URL];

            // If we haven't got any images, return.
            if (!images || ![images count])
                return NO;

            // Reopen the mp4v2 fileHandle
            if (![self startWriting])
                return NO;

            CGFloat maxWidth = 640;
            NSSize imageSize = [[images objectAtIndex:0] size];
            if (imageSize.width > maxWidth) {
                imageSize.height = maxWidth / imageSize.width * imageSize.height;
                imageSize.width = maxWidth;
            }
            NSRect rect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);

            jpegTrack = MP4AddJpegVideoTrack(self.fileHandle, MP4GetTrackTimeScale(self.fileHandle, [chapterTrack Id]),
                                             MP4_INVALID_DURATION, imageSize.width, imageSize.height);

            MP4SetTrackLanguage(self.fileHandle, jpegTrack, lang_for_english([refTrack.language UTF8String])->iso639_2);
            MP4SetTrackIntegerProperty(self.fileHandle, jpegTrack, "tkhd.layer", 1);
            MP4SetTrackDisabled(self.fileHandle, jpegTrack);

            for (NSUInteger idx = 0; idx < [[chapterTrack chapters] count]; idx++) {
                MP4Duration duration = MP4GetSampleDuration(self.fileHandle, chapterTrack.Id, idx + 1);

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

                if (idx < [images count]) {
                    [[images objectAtIndex:idx] drawInRect:rect fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
                }

                [NSGraphicsContext restoreGraphicsState];

                NSData *data = [bitmap representationUsingType:NSJPEGFileType properties:nil];
                [bitmap release];

                MP4WriteSample(self.fileHandle,
                               jpegTrack,
                               [data bytes],
                               [data length],
                               duration,
                               0,
                               true);
            }

            MP4RemoveAllTrackReferences(self.fileHandle, "tref.chap", refTrack.Id);
            MP4AddTrackReference(self.fileHandle, "tref.chap", chapterTrack.Id, refTrack.Id);
            MP4AddTrackReference(self.fileHandle, "tref.chap", jpegTrack, refTrack.Id);
            copyTrackEditLists(self.fileHandle, chapterTrack.Id, jpegTrack);

            [self stopWriting];
        }

        return YES;

    } else if (chapterTrack && jpegTrack) {
        // We already have all the tracks, so hook them up.
        if (![self startWriting])
            return NO;

        MP4RemoveAllTrackReferences(self.fileHandle, "tref.chap", refTrack.Id);
        MP4AddTrackReference(self.fileHandle, "tref.chap", chapterTrack.Id, refTrack.Id);
        MP4AddTrackReference(self.fileHandle, "tref.chap", jpegTrack, refTrack.Id);

        [self stopWriting];
    }

    return NO;
}

#pragma mark - Others

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt:2 forKey:@"MP42FileVersion"];

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
        [coder encodeObject:[NSURL fileURLWithPath:[self.URL path]] forKey:@"fileUrl"];
    } else {
        [coder encodeObject:self.URL forKey:@"fileUrl"];
    }
#endif

    [coder encodeObject:_tracksToBeDeleted forKey:@"tracksToBeDeleted"];
    [coder encodeBool:_hasFileRepresentation forKey:@"hasFileRepresentation"];

    [coder encodeObject:self.itracks forKey:@"tracks"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    NSData *bookmarkData = [decoder decodeObjectForKey:@"bookmark"];
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
        _fileURL = [[decoder decodeObjectForKey:@"fileUrl"] retain];
    }

    _tracksToBeDeleted = [[decoder decodeObjectForKey:@"tracksToBeDeleted"] retain];

    _hasFileRepresentation = [decoder decodeBoolForKey:@"hasFileRepresentation"];

    _tracks = [[decoder decodeObjectForKey:@"tracks"] retain];
    _metadata = [[decoder decodeObjectForKey:@"metadata"] retain];

    return self;
}

- (void)dealloc
{
    [_fileURL release];
    [_tracks release];
    [_importers release];
    [_tracksToBeDeleted release];
    [_metadata release];

    [super dealloc];
}

@end
