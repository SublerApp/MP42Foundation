//
//  MP42Track+Private.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 19/09/15.
//  Copyright © 2015 Damiano Galassi. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface MP42Track (Private)

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle;
- (BOOL)writeToFile:(MP42FileHandle)fileHandle error:(NSError **)outError;

@property(nonatomic, readwrite) MP42TrackId trackId;
@property(nonatomic, readwrite) MP42TrackId sourceId;

@property(nonatomic, readwrite, copy) NSURL *URL;

@property(nonatomic, readwrite) MP42CodecType format;
@property(nonatomic, readwrite) MP42MediaType mediaType;

@property(nonatomic, readwrite) MP42Duration duration;
@property(nonatomic, readwrite) uint32_t bitrate;
@property(nonatomic, readwrite) uint64_t dataLength;

@property(nonatomic, readwrite) BOOL isEdited;
@property(nonatomic, readwrite) BOOL muxed;

@property(nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *updatedProperty;

- (void *)copy_muxer_helper;
- (void *)create_muxer_helper;

@end

NS_ASSUME_NONNULL_END
