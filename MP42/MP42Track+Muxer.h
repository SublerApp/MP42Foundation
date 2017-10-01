//
//  MP42Track_MP42Track_Muxer.h
//  MP42
//
//  Created by Damiano Galassi on 01/11/13.
//  Copyright (c) 2013 Damiano Galassi. All rights reserved.
//

#import "MP42Track.h"
#import "MP42FileImporter.h"
#import "MP42ConverterProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface MP42Track (MP42TrackMuxerExtentions)

- (id <MP42ConverterProtocol>)converter;
- (void)setConverter:(id <MP42ConverterProtocol>)converter;

- (void)startReading;

- (void)enqueue:(MP42SampleBuffer *)sample;
- (MP42SampleBuffer *)copyNextSample;

- (void *)copy_muxer_helper;
- (void *)create_muxer_helper;
- (void)free_muxer_helper;

@end

NS_ASSUME_NONNULL_END
