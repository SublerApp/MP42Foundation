//
//  MP42FileImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2022 Damiano Galassi All rights reserved.
//

#import "MP42FileImporter.h"
#import "MP42FileImporter+Private.h"
#import "MP42MkvImporter.h"
#import "MP42Mp4Importer.h"
#import "MP42SrtImporter.h"
#import "MP42SSAImporter.h"
#import "MP42CCImporter.h"
#import "MP42AC3Importer.h"
#import "MP42AACImporter.h"
#import "MP42H264Importer.h"
#import "MP42VobSubImporter.h"
#import "MP42AVFImporter.h"

#import "MP42Track.h"
#import "MP42VideoTrack.h"
#import "MP42AudioTrack.h"
#import "MP42Track+Private.h"
#import "MP42SampleBuffer.h"
#import "MP42Metadata.h"

#import "mp4v2.h"

#import <CoreAudio/CoreAudio.h>

/// The available subclasses
static NSArray<Class> *_fileImporters;

/// The supporter file extentions.
static NSArray<NSString *> *_supportedFileFormats;

@implementation MP42FileImporter {
    NSMutableArray<MP42Track *> *_tracksArray;

    NSMutableArray<MP42Track *> *_inputTracks;
    NSMutableArray<MP42Track *> *_outputsTracks;

    NSThread *_demuxerThread;

    dispatch_semaphore_t _doneSem;

    _Atomic double _progress;
    _Atomic BOOL _cancelled;
}

+ (void)initialize {
    if (self == [MP42FileImporter class]) {
        _fileImporters = @[[MP42MkvImporter class],
                           [MP42Mp4Importer class],
                           [MP42SrtImporter class],
                           [MP42CCImporter class],
                           [MP42AACImporter class],
                           [MP42H264Importer class],
                           [MP42VobSubImporter class],
                           [MP42AVFImporter class],
                           [MP42AC3Importer class],
                           [MP42SSAImporter class]];

        NSMutableArray<NSString *> *formats = [[NSMutableArray alloc] init];

        for (Class c in _fileImporters) {
            [formats addObjectsFromArray:[c supportedFileFormats]];
        }

        _supportedFileFormats = [formats copy];
    }
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return _supportedFileFormats;
}

+ (BOOL)canInitWithFileType:(NSString *)fileType {
    return [[self supportedFileFormats] containsObject:fileType.lowercaseString];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError * __autoreleasing *)error
{
    self = nil;

    // Initialize the right file importer subclass
    for (Class c in _fileImporters) {
        if ([c canInitWithFileType:fileURL.pathExtension]) {

            self = [[c alloc] initWithURL:fileURL error:error];
            if (self) {
                for (MP42Track *track in _tracksArray) {
                    track.importer = self;
                }

                break;
            }
        }
    }

    return self;
}

- (instancetype)initWithURL:(NSURL *)fileURL
{
    self = [super init];
    if (self) {
        _fileURL = fileURL;
        _tracksArray = [[NSMutableArray alloc] init];
        _doneSem = dispatch_semaphore_create(0);
        _metadata = [[MP42Metadata alloc] init];
    }
    return self;
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
    return [_inputTracks copy];
}

- (NSArray<MP42Track *> *)outputsTracks
{
    return [_outputsTracks copy];
}

- (void)setMetadata:(MP42Metadata * _Nonnull)metadata
{
    _metadata = metadata;
}

@synthesize tracks = _tracksArray;

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
        [track startReading];
    }

    if (!_demuxerThread) {
        _demuxerThread = [[NSThread alloc] initWithTarget:self selector:@selector(demux) object:nil];
        _demuxerThread.name = self.description;
        _demuxerThread.qualityOfService = NSQualityOfServiceUtility;

        [_demuxerThread start];
    }
}

- (void)cancelReading
{
    _cancelled = YES;

    // wait until the demuxer thread exits
    dispatch_semaphore_wait(_doneSem, DISPATCH_TIME_FOREVER);
}

- (void)enqueue:(MP42SampleBuffer * NS_RELEASES_ARGUMENT)sample
{
    for (MP42Track *track in _outputsTracks) {
        if (track.sourceId == sample->trackId) {
            [track enqueue:sample];
        }
    }
}

/**
 * Sends the EOF flag down the muxer chain.
 */
- (void)enqueueEndOfFileSamples
{
    for (MP42Track *track in _outputsTracks) {
        MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
        sample->flags |= MP42SampleBufferFlagEndOfFile;
        sample->trackId = track.sourceId;
        [track enqueue:sample];
    }
}

- (void)setDone
{
    [self enqueueEndOfFileSamples];
    dispatch_semaphore_signal(_doneSem);
}

- (void)setProgress:(double)progress
{
    _progress = progress;
}

- (double)progress
{
    return _progress;
}

- (BOOL)isCancelled
{
    return _cancelled;
}

#pragma mark - Override

- (nullable NSData *)magicCookieForTrack:(MP42Track *)track
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (AudioStreamBasicDescription)audioDescriptionForTrack:(MP42AudioTrack *)track
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (void)setup {}

- (void)demux
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (BOOL)audioTrackUsesExplicitEncoderDelay:(MP42Track *)track
{
    return NO;
}

- (BOOL)supportsPreciseTimestamps
{
    return NO;
}

- (void)cleanUp:(MP42Track *)track fileHandle:(MP4FileHandle)fileHandle {}

@end
