//
//  MP42SubtitleTrack.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import "MP42ClosedCaptionTrack.h"
#import "MP42Track+Private.h"
#import "MP42MediaFormat.h"

@implementation MP42ClosedCaptionTrack

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle
{
    self = [super initWithSourceURL:URL trackID:trackID fileHandle:fileHandle];

    if (self) {
        _mediaType = kMP42MediaType_ClosedCaption;
    }

    return self;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _name = [self defaultName];
        _format = kMP42ClosedCaptionCodecType_CEA608;
        _mediaType = kMP42MediaType_ClosedCaption;
    }

    return self;
}

- (BOOL)writeToFile:(MP42FileHandle)fileHandle error:(NSError **)outError
{
    if (_isEdited && !_muxed) {
        _muxed = YES;
    }

    [super writeToFile:fileHandle error:outError];

    return (_trackId > 0);
}

- (NSString *)defaultName {
    // TODO
    return @"Closed Caption";
    //return kMP42MediaType_ClosedCaption;
}

- (void)dealloc
{
    [super dealloc];
}

@end
