//
//  MP42Track+Private.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 19/09/15.
//  Copyright © 2015 Damiano Galassi. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class MP42FileImporter;
@class MP42SampleBuffer;
@protocol MP42ConverterProtocol;

@interface MP42Track (Private)

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle;
- (BOOL)writeToFile:(MP42FileHandle)fileHandle error:(NSError **)outError;

@property(nonatomic, readwrite) MP42TrackId trackId;
@property(nonatomic, readwrite) MP42TrackId sourceId;

@property(nonatomic, readwrite, copy) NSURL *URL;

@property(nonatomic, readonly) MP42CodecType targetFormat;
@property(nonatomic, readwrite) MP42CodecType format;
@property(nonatomic, readwrite) MP42MediaType mediaType;

@property(nonatomic, readwrite) MP42Duration duration;
@property(nonatomic, readwrite) uint32_t bitrate;
@property(nonatomic, readwrite) uint64_t dataLength;

@property(nonatomic, readwrite, getter=isEdited) BOOL edited;
@property(nonatomic, readwrite) BOOL muxed;

@property(nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *updatedProperty;

@property (nonatomic, readwrite) MP42FileImporter *importer;

@property (nonatomic, readwrite) id<MP42ConverterProtocol> converter;
@property (nonatomic, readwrite) id demuxerHelper;

- (MP42SampleBuffer *)copyNextSample;

- (void *)copy_muxer_helper;
- (void *)create_muxer_helper;

@end

NS_ASSUME_NONNULL_END
