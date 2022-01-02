//
//  MP42SubtitleTrack.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42ClosedCaptionTrack.h"
#import "MP42Track+Private.h"
#import "MP42MediaFormat.h"

@implementation MP42ClosedCaptionTrack

- (instancetype)init
{
    if ((self = [super init])) {
        self.format = kMP42ClosedCaptionCodecType_CEA608;
        self.mediaType = kMP42MediaType_ClosedCaption;
    }

    return self;
}

- (BOOL)writeToFile:(MP42FileHandle)fileHandle error:(NSError * __autoreleasing *)outError
{
    return [super writeToFile:fileHandle error:outError];
}

@end
