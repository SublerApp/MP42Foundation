//
//  MP42Track_MP42Track_Muxer.h
//  MP42
//
//  Created by Damiano Galassi on 01/11/13.
//  Copyright (c) 2013 Damiano Galassi. All rights reserved.
//

#import "MP42Track.h"
#import "MP42FileImporter.h"
#import "MP42Fifo.h"
#import "MP42ConverterProtocol.h"

typedef struct muxer_helper {
    // Input helpers
    MP42FileImporter *importer;
    id demuxer_context;

    // Output helpers
    id <MP42ConverterProtocol> converter;
    MP42Fifo *fifo;

    BOOL done;
} muxer_helper;

@interface MP42Track (MP42TrackMuxerExtentions)

@property(nonatomic, readonly) muxer_helper *muxer_helper;

- (MP42SampleBuffer *)copyNextSample;

@end
