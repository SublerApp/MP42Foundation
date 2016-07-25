//
//  MP42Muxer.h
//  Subler
//
//  Created by Damiano Galassi on 30/06/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "mp4v2.h"
#import "MP42Logging.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42Track;

@protocol MP42MuxerDelegate
- (void)progressStatus:(double)progress;
@end

@interface MP42Muxer : NSObject

- (instancetype)initWithFileHandle:(MP4FileHandle)fileHandle delegate:(id <MP42MuxerDelegate>)del logger:(id <MP42Logging>)logger;

- (BOOL)canAddTrack:(MP42Track *)track;
- (void)addTrack:(MP42Track *)track;

- (BOOL)setup:(NSError **)outError;
- (void)work;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
