//
//  MP42SubtitleTrack.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42Track.h"

@interface MP42AudioTrack : MP42Track <NSCoding, NSCopying> {
@private
    float _volume;
    UInt32 _channels;
    UInt32 _sourceChannels;
    UInt32 _channelLayoutTag;

    MP42TrackId  _fallbackTrackId;
    MP42TrackId  _followsTrackId;

    MP42Track  *_fallbackTrack;
    MP42Track  *_followsTrack;
    
    NSString *_mixdownType;
}

@property(nonatomic, readwrite) float volume;
@property(nonatomic, readwrite) UInt32 channels;
@property(nonatomic, readwrite) UInt32 sourceChannels;
@property(nonatomic, readwrite) UInt32 channelLayoutTag;

@property(nonatomic, readonly) MP42TrackId fallbackTrackId;
@property(nonatomic, readonly) MP42TrackId followsTrackId;

@property(nonatomic, readwrite, assign) MP42Track *fallbackTrack;
@property(nonatomic, readwrite, assign) MP42Track *followsTrack;

@property(nonatomic, readwrite, copy) NSString *mixdownType;

@end
