//
//  MP42Track.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42Utilities.h>
#import <MP42Foundation/MP42ConversionSettings.h>
#import <MP42Foundation/MP42SecurityAccessToken.h>

@class MP42SampleBuffer;
@class MP42SampleDescription;

NS_ASSUME_NONNULL_BEGIN

/**
 *  MP42Track
 */
@interface MP42Track : NSObject <NSSecureCoding, NSCopying, MP42SecurityScope>

@property(nonatomic, readonly) MP42TrackId trackId;

@property(nonatomic, readonly, copy, nullable) NSURL *URL;

@property(nonatomic, readonly) NSArray<MP42SampleDescription *> *sampleDescriptions;

@property(nonatomic, readonly) MP42MediaType mediaType;
@property(nonatomic, readonly) MP42CodecType format;

@property(nonatomic, readonly) uint32_t timescale;
@property(nonatomic, readonly) MP42Duration duration;

@property(nonatomic, readonly) uint32_t bitrate;
@property(nonatomic, readonly) uint64_t dataLength;
@property(nonatomic, readonly, getter=isMuxed) BOOL muxed;

@property(nonatomic, readwrite, getter=isEnabled) BOOL enabled;

@property(nonatomic, readwrite, copy) NSString *name;
@property(nonatomic, readwrite, copy) NSString *language;

@property(nonatomic, readwrite, copy) NSSet<NSString *> *mediaCharacteristicTags;

@property(nonatomic, readwrite) uint64_t alternateGroup;
@property(nonatomic, readwrite) NSTimeInterval startOffset;

@property(nonatomic, readwrite, copy, nullable) MP42ConversionSettings *conversionSettings;

@property (nonatomic, readonly) NSString *timeString;
@property (nonatomic, readonly) NSString *formatSummary;

@property (nonatomic, readonly) BOOL canExport;
- (BOOL)exportToURL:(NSURL *)url error:(NSError * __autoreleasing *)error;

#pragma mark - Private

- (void)enqueue:(MP42SampleBuffer *)sample MP42_OBJC_DIRECT;
- (nullable MP42SampleBuffer *)copyNextSample MP42_OBJC_DIRECT;

@end

NS_ASSUME_NONNULL_END
