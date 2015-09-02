//
//  MP42FileImporter.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "MP42MediaFormat.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42Metadata;
@class MP42Track;

@interface MP42FileImporter : NSObject {
@protected
    NSURL   *_fileURL;

    NSInteger       _chapterId;
    MP42Metadata   *_metadata;

    NSMutableArray<MP42Track *> *_tracksArray;
    NSMutableArray<MP42Track *> *_inputTracks;
    NSMutableArray<MP42Track *> *_outputsTracks;
    NSThread       *_demuxerThread;

    CGFloat       _progress;
    int32_t       _cancelled;
    int32_t       _done;

@private
    dispatch_semaphore_t _doneSem;
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)error;

- (BOOL)containsTrack:(MP42Track *)track;
- (MP42Track *)inputTrackWithTrackID:(MP42TrackId)trackId;

- (NSUInteger)timescaleForTrack:(MP42Track *)track;
- (NSSize)sizeForTrack:(MP42Track *)track;
- (nullable NSData *)magicCookieForTrack:(MP42Track *)track;
- (AudioStreamBasicDescription)audioDescriptionForTrack:(MP42Track *)track;

- (void)setActiveTrack:(MP42Track *)track;

- (void)startReading;
- (void)cancelReading;

- (void)enqueue:(MP42SampleBuffer *)sample;

- (CGFloat)progress;

- (BOOL)done;
- (void)setDone:(BOOL)status;

- (BOOL)cleanUp:(MP42FileHandle)fileHandle;

@property(nonatomic, readonly) MP42Metadata *metadata;
@property(nonatomic, readonly) NSArray<MP42Track *> *tracks;

@end

NS_ASSUME_NONNULL_END
