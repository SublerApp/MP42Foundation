//
//  MP42FileImporter+Private.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 05/09/15.
//  Copyright © 2015 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "MP42MediaFormat.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;

@interface MP42FileImporter (Private)

- (instancetype)initWithURL:(NSURL *)fileURL;

@property(nonatomic, readwrite) MP42Metadata *metadata;

- (void)addTrack:(MP42Track *)track;
- (void)addTracks:(NSArray<MP42Track *> *)tracks;

@property (nonatomic, copy) NSArray<MP42Track *> *inputTracks;
@property (nonatomic, copy) NSArray<MP42Track *> *outputsTracks;

- (MP42Track *)inputTrackWithTrackID:(MP42TrackId)trackId;

- (void)setActiveTrack:(MP42Track *)track;

- (void)startReading;
- (void)cancelReading;

- (void)enqueue:(MP42SampleBuffer *)sample;

@property (nonatomic, readwrite) double progress;
@property (nonatomic, readonly, getter=isCancelled) BOOL cancelled;

- (void)setDone;

@end

@interface MP42FileImporter (Override)

- (NSUInteger)timescaleForTrack:(MP42Track *)track;
- (NSSize)sizeForTrack:(MP42Track *)track;
- (nullable NSData *)magicCookieForTrack:(MP42Track *)track;
- (AudioStreamBasicDescription)audioDescriptionForTrack:(MP42Track *)track;
- (BOOL)cleanUp:(MP42FileHandle)fileHandle;

- (BOOL)audioTrackUsesExplicitEncoderDelay:(MP42Track *)track;
- (BOOL)supportsPreciseTimestamps;

@end

NS_ASSUME_NONNULL_END
