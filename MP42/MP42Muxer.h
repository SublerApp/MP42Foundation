//
//  MP42Muxer.h
//  Subler
//
//  Created by Damiano Galassi on 30/06/10.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "mp4v2.h"
#import "MP42Logging.h"
#import "MP42Utilities.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42Track;

@protocol MP42MuxerDelegate
- (void)progressStatus:(double)progress;
@end

MP42_OBJC_DIRECT_MEMBERS
@interface MP42Muxer : NSObject

- (instancetype)initWithFileHandle:(MP4FileHandle)fileHandle delegate:(id <MP42MuxerDelegate>)del logger:(id <MP42Logging>)logger options:(nullable NSDictionary<NSString *, id> *)options;

- (BOOL)canAddTrack:(MP42Track *)track;
- (void)addTrack:(MP42Track *)track;

- (BOOL)setup:(NSError * __autoreleasing *)outError;
- (void)work;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
