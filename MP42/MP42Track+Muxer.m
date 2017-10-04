//
//  MP42Track_MP42Track_Muxer.h
//  MP42
//
//  Created by Damiano Galassi on 01/11/13.
//  Copyright (c) 2013 Damiano Galassi. All rights reserved.
//

#import "MP42Track+Muxer.h"
#import "MP42FileImporter+Private.h"
#import "MP42Fifo.h"

typedef struct muxer_helper {
    // Input helpers
    MP42FileImporter *importer;

    // Output helpers
    id <MP42ConverterProtocol> converter;
    MP42Fifo<MP42SampleBuffer *> *fifo;
} muxer_helper;

@interface MP42Track (MP42TrackMuxerExtensions)

@property (nonatomic, readonly, nullable) muxer_helper *muxer_helper;

@end

@implementation MP42Track (MP42TrackMuxerExtentions)

- (MP42FileImporter *)importer
{
    muxer_helper *helper = (muxer_helper *)_helper;
    return helper ? helper->importer : nil;
}

- (void)setImporter:(MP42FileImporter *)importer
{
    self.muxer_helper->importer = importer;
}

- (id <MP42ConverterProtocol>)converter
{
    muxer_helper *helper = (muxer_helper *)_helper;
    return helper->converter;
}

- (void)setConverter:(id <MP42ConverterProtocol>)converter
{
    self.muxer_helper->converter = [converter retain];
}

- (void *)copy_muxer_helper
{
    muxer_helper *copy = calloc(1, sizeof(muxer_helper));
    copy->importer = ((muxer_helper *)_helper)->importer;

    return copy;
}

- (void *)create_muxer_helper
{
    muxer_helper *helper = calloc(1, sizeof(muxer_helper));
    return helper;
}

- (void)free_muxer_helper
{
    muxer_helper *helper = (muxer_helper *)_helper;
    if (helper) {
        [helper->fifo release];
        [helper->converter release];
        free(helper);
    }
}

- (void)startReading
{
    self.muxer_helper->fifo = [[MP42Fifo alloc] init];
}

- (void)enqueue:(MP42SampleBuffer *)sample
{
    muxer_helper *helper = (muxer_helper *)_helper;
    if (helper->converter) {
        [helper->converter addSample:sample];
    } else {
        [helper->fifo enqueue:sample];
    }
}

- (MP42SampleBuffer *)copyNextSample {
    muxer_helper *helper = (muxer_helper *)_helper;

    if (helper->converter) {
        return [helper->converter copyEncodedSample];
    }
    else {
        return [helper->fifo dequeue];
    }
}

@end
