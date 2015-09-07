//
//  MP42FileImporter.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42Metadata;
@class MP42Track;

@interface MP42FileImporter : NSObject {
@protected
    NSInteger       _chapterId;
    MP42Metadata   *_metadata;

    CGFloat       _progress;
    int32_t       _cancelled;

@private
    NSURL    *_fileURL;

    NSMutableArray<MP42Track *> *_tracksArray;

    NSMutableArray<MP42Track *> *_inputTracks;
    NSMutableArray<MP42Track *> *_outputsTracks;

    NSThread *_demuxerThread;

    int32_t  _done;
    dispatch_semaphore_t _doneSem;
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)error;

@property(nonatomic, readonly) NSURL *fileURL;
@property(nonatomic, readonly) MP42Metadata *metadata;
@property(nonatomic, readonly) NSArray<MP42Track *> *tracks;

@end

NS_ASSUME_NONNULL_END
