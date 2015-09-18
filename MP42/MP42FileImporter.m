//
//  MP42FileImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import "MP42FileImporter.h"
#import "MP42MkvImporter.h"
#import "MP42Mp4Importer.h"
#import "MP42SrtImporter.h"
#import "MP42CCImporter.h"
#import "MP42AC3Importer.h"
#import "MP42AACImporter.h"
#import "MP42H264Importer.h"
#import "MP42VobSubImporter.h"
#import "MP42Track.h"
#import "MP42Fifo.h"

#if !__LP64__
#import "MP42QTImporter.h"
#endif

#import "MP42AVFImporter.h"

#import "MP42AudioConverter.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Muxer.h"

@implementation MP42FileImporter

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"scc", @"smi",  @"txt", @"m4v", @"mp4",
             @"m4a", @"m4a", @"mov", @"ts", @"mts",
             @"m2ts", @"mkv", @"mka", @"mks", @"h264",
             @"264", @"idx", @"aac", @"ac3", @"eac3", @"srt"];
}

+ (BOOL)canInitWithFileType:(NSString *)fileType {
    return [[MP42FileImporter supportedFileFormats] containsObject:fileType.lowercaseString];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)error;
{
    [self release];
    self = nil;

    NSString *pathExtension = fileURL.pathExtension;

    if ([pathExtension caseInsensitiveCompare: @"mkv"] == NSOrderedSame ||
        [pathExtension caseInsensitiveCompare: @"mka"] == NSOrderedSame ||
        [pathExtension caseInsensitiveCompare: @"mks"] == NSOrderedSame) {
        self = [MP42MkvImporter alloc];
    }
    else if ([pathExtension caseInsensitiveCompare: @"mp4"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"m4v"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"m4a"] == NSOrderedSame) {
        self = [MP42Mp4Importer alloc];
    }
    else if ([pathExtension caseInsensitiveCompare: @"srt"] == NSOrderedSame) {
        self = [MP42SrtImporter alloc];
    }
    else if ([pathExtension caseInsensitiveCompare: @"scc"] == NSOrderedSame) {
        self = [MP42CCImporter alloc];
    }
    else if ([pathExtension caseInsensitiveCompare: @"ac3"] == NSOrderedSame) {
        self = [MP42AC3Importer alloc];
    }
    else if ([pathExtension caseInsensitiveCompare: @"aac"] == NSOrderedSame) {
        self = [MP42AACImporter alloc];
    }
    else if ([pathExtension caseInsensitiveCompare: @"264"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"h264"] == NSOrderedSame) {
        self = [MP42H264Importer alloc];
    }
    else if ([pathExtension caseInsensitiveCompare: @"idx"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"idx"] == NSOrderedSame) {
        self = [MP42VobSubImporter alloc];
    }
#if !__LP64__
    /*else if ([pathExtension caseInsensitiveCompare: @"mov"] == NSOrderedSame) {
        self = [MP42QTImporter alloc];
    }*/
#endif
    else if ([pathExtension caseInsensitiveCompare: @"m2ts"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"ts"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"mts"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"mov"] == NSOrderedSame ||
             [pathExtension caseInsensitiveCompare: @"eac3"] == NSOrderedSame) {
        self = [MP42AVFImporter alloc];
    }

    if (self) {
        self = [self initWithURL:fileURL error:error];

        if (self) {
            for (MP42Track *track in _tracksArray)
                track.muxer_helper->importer = self;
        }
    }

    return self;
}

- (instancetype)initWithURL:(NSURL *)fileURL
{
    self = [super init];
    if (self) {
        _fileURL = [fileURL retain];
        _tracksArray = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    for (MP42Track *track in _inputTracks) {
        [track.muxer_helper->demuxer_context release];
    }

    for (MP42Track *track in _outputsTracks) {
        [track.muxer_helper->fifo release];
        [track.muxer_helper->converter release];
    }

    [_metadata release], _metadata = nil;
    [_tracksArray release], _tracksArray = nil;
    [_inputTracks release], _inputTracks = nil;
    [_outputsTracks release], _outputsTracks = nil;

    [_fileURL release], _fileURL = nil;
    [_demuxerThread release], _demuxerThread = nil;

    if (_doneSem) {
        dispatch_release(_doneSem);
    }

    [super dealloc];
}

- (NSURL *)fileURL
{
    return _fileURL;
}

- (void)addTrack:(MP42Track *)track
{
    [_tracksArray addObject:track];
}

- (void)addTracks:(NSArray<MP42Track *> *)tracks
{
    [_tracksArray addObjectsFromArray:tracks];
}

- (NSArray<MP42Track *> *)inputTracks
{
    return [[_inputTracks copy] autorelease];
}

- (NSArray<MP42Track *> *)outputsTracks
{
    return [[_outputsTracks copy] autorelease];
}

@synthesize metadata = _metadata;
@synthesize tracks = _tracksArray;

- (NSUInteger)timescaleForTrack:(MP42Track *)track
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (NSSize)sizeForTrack:(MP42Track *)track
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (nullable NSData *)magicCookieForTrack:(MP42Track *)track
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (AudioStreamBasicDescription)audioDescriptionForTrack:(MP42Track *)track
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (void)demux
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (BOOL)cleanUp:(MP4FileHandle)fileHandle
{
    return YES;
}

- (void)setActiveTrack:(MP42Track *)track {
    if (!_inputTracks) {
        _inputTracks = [[NSMutableArray alloc] init];
        _outputsTracks = [[NSMutableArray alloc] init];
    }

    BOOL alreadyAdded = NO;
    for (MP42Track *inputTrack in _inputTracks) {
        if (inputTrack.sourceId == track.sourceId) {
            alreadyAdded = YES;
        }
    }

    if (!alreadyAdded) {
        [_inputTracks addObject:track];
    }

    [_outputsTracks addObject:track];
}

- (void)startReading
{
    for (MP42Track *track in _outputsTracks) {
        track.muxer_helper->fifo = [[MP42Fifo alloc] init];
    }

    _doneSem = dispatch_semaphore_create(0);

    if (!_demuxerThread && !_done) {
        _demuxerThread = [[NSThread alloc] initWithTarget:self selector:@selector(demux) object:nil];
        _demuxerThread.name = self.description;

        // 10.10+
        if ([_demuxerThread respondsToSelector:@selector(setQualityOfService:)]) {
            _demuxerThread.qualityOfService = NSQualityOfServiceUtility;
        }

        [_demuxerThread start];
    }
}

- (void)cancelReading
{
    OSAtomicIncrement32(&_cancelled);

    for (MP42Track *track in _outputsTracks) {
        [track.muxer_helper->fifo cancel];
    }

    // wait until the demuxer thread exits
    dispatch_semaphore_wait(_doneSem, DISPATCH_TIME_FOREVER);

    // stop all the related converters
    for (MP42Track *track in _outputsTracks) {
        [track.muxer_helper->converter cancel];
    }
}

- (void)enqueue:(MP42SampleBuffer *)sample
{
    for (MP42Track *track in _outputsTracks) {
        if (track.sourceId == sample->trackId) {
            if (track.muxer_helper->converter) {
                [track.muxer_helper->converter addSample:sample];
            } else {
                [track.muxer_helper->fifo enqueue:sample];
            }
        }
    }
}

- (BOOL)done
{
    return (_done > 0);
}

- (void)setDone
{
    OSAtomicIncrement32(&_done);
    dispatch_semaphore_signal(_doneSem);
}

- (CGFloat)progress
{
    return _progress;
}

- (BOOL)containsTrack:(MP42Track *)track
{
    return [_tracksArray containsObject:track];
}

- (MP42Track *)inputTrackWithTrackID:(MP4TrackId)trackId
{
    for (MP42Track *track in _inputTracks) {
        if (track.sourceId == trackId) {
            return track;;
        }
    }

    return nil;
}

@end
