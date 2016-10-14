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

@dynamic muxer_helper;

- (MP42FileImporter *)importer
{
    return self.muxer_helper->importer;
}

- (void)setImporter:(MP42FileImporter *)importer
{
    self.muxer_helper->importer = importer;
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
