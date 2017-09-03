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
#import "MP42AVFImporter.h"

#import "MP42Track.h"
#import "MP42Fifo.h"

#import "MP42AudioConverter.h"
#import "MP42Track+Muxer.h"
#import "MP42Track+Private.h"

#import <CoreAudio/CoreAudio.h>

/// The available subclasses
static NSArray<Class> *_fileImporters;

/// The supporter file extentions.
static NSArray<NSString *> *_supportedFileFormats;

@implementation MP42FileImporter {
@private
    NSURL    *_fileURL;

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
        _fileImporters = [@[[MP42MkvImporter class],
                           [MP42Mp4Importer class],
                           [MP42SrtImporter class],
                           [MP42CCImporter class],
                           [MP42AACImporter class],
                           [MP42H264Importer class],
                           [MP42VobSubImporter class],
                           [MP42AVFImporter class],
                           [MP42AC3Importer class]] retain];

        NSMutableArray<NSString *> *formats = [[NSMutableArray alloc] init];

        for (Class c in _fileImporters) {
            [formats addObjectsFromArray:[c supportedFileFormats]];
        }

        _supportedFileFormats = [formats copy];
        [formats release];
    }
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return _supportedFileFormats;
}

+ (BOOL)canInitWithFileType:(NSString *)fileType {
    return [[self supportedFileFormats] containsObject:fileType.lowercaseString];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)error;
{
    [self release];
    self = nil;

    // Initialize the right file importer subclass
    for (Class c in _fileImporters) {
        if ([c canInitWithFileType:fileURL.pathExtension]) {

            [self release];

            self = [[c alloc] initWithURL:fileURL error:error];
            if (self) {
                for (MP42Track *track in _tracksArray) {
                    track.muxer_helper->importer = self;
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

    [_metadata release];
    [_tracksArray release]; _tracksArray = nil;
    [_inputTracks release]; _inputTracks = nil;
    [_outputsTracks release]; _outputsTracks = nil;

    [_fileURL release]; _fileURL = nil;
    [_demuxerThread release]; _demuxerThread = nil;

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

- (void)setMetadata:(MP42Metadata * _Nonnull)metadata
{
    _metadata = [metadata retain];
}

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

- (BOOL)audioTrackUsesExplicitEncoderDelay:(MP42Track *)track;
{
    return NO;
}

- (BOOL)supportsPreciseTimestamps
{
    return NO;
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

    if (!_demuxerThread) {
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
    _cancelled = YES;

    // wait until the demuxer thread exits
    dispatch_semaphore_wait(_doneSem, DISPATCH_TIME_FOREVER);
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

/**
 * Sends the EOF flag down the muxer chain.
 */
- (void)enqueueEndOfFileSamples
{
    for (MP42Track *track in _outputsTracks) {
        MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
        sample->flags |= MP42SampleBufferFlagEndOfFile;

        if (track.muxer_helper->converter) {
            [track.muxer_helper->converter addSample:sample];
        } else {
            [track.muxer_helper->fifo enqueue:sample];
        }
        [sample release];
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
