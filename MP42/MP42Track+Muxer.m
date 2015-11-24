//
//  MP42Track_MP42Track_Muxer.h
//  MP42
//
//  Created by Damiano Galassi on 01/11/13.
//  Copyright (c) 2013 Damiano Galassi. All rights reserved.
//

#import "MP42Track+Muxer.h"
#import "MP42FileImporter+Private.h"

@implementation MP42Track (MP42TrackMuxerExtentions)

- (muxer_helper *)muxer_helper
{
    if (_helper == NULL) {
        _helper = calloc(1, sizeof(muxer_helper));
    }

    return _helper;
}

- (MP42SampleBuffer *)copyNextSample {
    MP42SampleBuffer *sample = nil;
    muxer_helper *helper = (muxer_helper *)_helper;

    if (helper->converter) {
        if ([helper->importer done]) {
            [helper->converter setInputDone];
        }

        if ([helper->converter encoderDone]) {
            helper->done = YES;
        }

        sample = [helper->converter copyEncodedSample];
    }
    else {
        if ([helper->fifo isEmpty] && [helper->importer done]) {
            helper->done = YES;
        }

        sample = [helper->fifo dequeue];
    }

    return sample;
}


@end
