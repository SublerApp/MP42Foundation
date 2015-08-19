//
//  MP42SubtitleTrack.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42VideoTrack.h"

NS_ASSUME_NONNULL_BEGIN

@interface MP42SubtitleTrack : MP42VideoTrack <NSCoding> {
@private
    BOOL _verticalPlacement;
    BOOL _someSamplesAreForced;
    BOOL _allSamplesAreForced;

    MP42TrackId  _forcedTrackId;
    MP42Track  *_forcedTrack;
}

- (BOOL)exportToURL:(NSURL *)url error:(NSError **)error;

@property(nonatomic, readwrite) BOOL verticalPlacement;
@property(nonatomic, readwrite) BOOL someSamplesAreForced;
@property(nonatomic, readwrite) BOOL allSamplesAreForced;

@property(nonatomic, readonly)  MP42TrackId forcedTrackId;
@property(nonatomic, readwrite, assign, nullable) MP42Track *forcedTrack;

@end

NS_ASSUME_NONNULL_END
