//
//  MP42SubtitleTrack.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import "MP42VideoTrack.h"
#import "MP42Track+Private.h"
#import "MP42MediaFormat.h"
#import "MP42Track+Private.h"
#import <mp4v2.h>

@implementation MP42VideoTrack
{
    uint64_t _width, _height;
    float _trackWidth, _trackHeight;

    // Pixel Aspect Ratio
    uint64_t _hSpacing, _vSpacing;

    // Clean Aperture
    uint64_t _cleanApertureWidthN, _cleanApertureWidthD;
    uint64_t _cleanApertureHeightN, _cleanApertureHeightD;
    uint64_t _horizOffN, _horizOffD;
    uint64_t _vertOffN, _vertOffD;

    // Matrix
    uint32_t _offsetX, _offsetY;

    // H.264 profile
    uint8_t _origProfile, _origLevel;
    uint8_t _newProfile, _newLevel;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle
{
    self = [super initWithSourceURL:URL trackID:trackID fileHandle:fileHandle];

    if (self) {

        if ([self isMemberOfClass:[MP42VideoTrack class]]) {
            _height = MP4GetTrackVideoHeight(fileHandle, self.trackId);
            _width = MP4GetTrackVideoWidth(fileHandle, self.trackId);
        }

        MP4GetTrackFloatProperty(fileHandle, self.trackId, "tkhd.width", &_trackWidth);
        MP4GetTrackFloatProperty(fileHandle, self.trackId, "tkhd.height", &_trackHeight);

        uint8_t *val;
        uint8_t nval[36];
        uint32_t *ptr32 = (uint32_t*) nval;
        uint32_t size;

        MP4GetTrackBytesProperty(fileHandle ,self.trackId, "tkhd.matrix", &val, &size);
        memcpy(nval, val, size);
        _offsetX = CFSwapInt32BigToHost(ptr32[6]) / 0x10000;
        _offsetY = CFSwapInt32BigToHost(ptr32[7]) / 0x10000;
        free(val);

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp")) {
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp.hSpacing", &_hSpacing);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp.vSpacing", &_vSpacing);
        }
        else {
            _hSpacing = 1;
            _vSpacing = 1;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap")) {
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureWidthN", &_cleanApertureWidthN);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureWidthD", &_cleanApertureWidthD);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureHeightN", &_cleanApertureHeightN);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureHeightD", &_cleanApertureHeightD);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.horizOffN", &_horizOffN);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.horizOffD", &_horizOffD);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.vertOffN", &_vertOffN);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.vertOffD", &_vertOffD);
        }

        if (self.format == kMP42VideoCodecType_H264) {
            MP4GetTrackH264ProfileLevel(fileHandle, (MP4TrackId)trackID, &_origProfile, &_origLevel);
            _newProfile = _origProfile;
            _newLevel = _origLevel;
        }
    }

    return self;
}

- (instancetype)init
{
    self = [super initWithFormat:0 mediaType:kMP42MediaType_Video enabled:YES language:@"Unknown"];
    return self;
}

- (BOOL)writeToFile:(MP4FileHandle)fileHandle error:(NSError **)outError
{
    if (!fileHandle) {
        return NO;
    }

    if (self.trackId) {
        [super writeToFile:fileHandle error:outError];

        if (_trackWidth > 0 && _trackHeight > 0) {
            MP4SetTrackFloatProperty(fileHandle, self.trackId, "tkhd.width", _trackWidth);
            MP4SetTrackFloatProperty(fileHandle, self.trackId, "tkhd.height", _trackHeight);

            uint8_t *val;
            uint8_t nval[36];
            uint32_t *ptr32 = (uint32_t*) nval;
            uint32_t size;

            MP4GetTrackBytesProperty(fileHandle ,self.trackId, "tkhd.matrix", &val, &size);
            memcpy(nval, val, size);
            ptr32[6] = CFSwapInt32HostToBig(_offsetX * 0x10000);
            ptr32[7] = CFSwapInt32HostToBig(_offsetY * 0x10000);
            MP4SetTrackBytesProperty(fileHandle, self.trackId, "tkhd.matrix", nval, size);

            free(val);

            if (self.updatedProperty[@"hSpacing"] || self.updatedProperty[@"vSpacing"]) {
                if (_hSpacing >= 1 && _vSpacing >= 1) {
                    if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp")) {
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp.hSpacing", _hSpacing);
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp.vSpacing", _vSpacing);
                    }
                    else {
                        MP4AddPixelAspectRatio(fileHandle, self.trackId, (uint32_t)_hSpacing, (uint32_t)_vSpacing);
                    }
                }
            }

            if (_cleanApertureWidthN >= 1 && _cleanApertureHeightN >= 1) {
                    if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap")) {
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureWidthN", _cleanApertureWidthN);
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureWidthD", _cleanApertureWidthD);
                        
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureHeightN", _cleanApertureHeightN);
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.cleanApertureHeightD", _cleanApertureHeightD);
                        
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.horizOffN", _horizOffN);
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.horizOffD", _horizOffD);
                        
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.vertOffN", _vertOffN);
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clap.vertOffD", _vertOffD);
                    }
                    else
                        MP4AddCleanAperture(fileHandle, self.trackId, _cleanApertureWidthN, _cleanApertureWidthD, _cleanApertureHeightN, _cleanApertureHeightD,
                                            _horizOffN, _horizOffD, _vertOffN, _vertOffD);
            }

            if (self.format == kMP42VideoCodecType_H264) {
                if (self.updatedProperty[@"profile"]) {
                    MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*[0].avcC.AVCProfileIndication", _newProfile);
                    _origProfile = _newProfile;
                }
                if (self.updatedProperty[@"level"]) {
                    MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*[0].avcC.AVCLevelIndication", _newLevel);
                    _origLevel = _newLevel;
                }
            }
        }
    }

    return (self.trackId > 0);
}

- (uint64_t)hSpacing {
    return _hSpacing;
}

- (void)setHSpacing:(uint64_t)newHSpacing
{
    _hSpacing = newHSpacing;
    self.isEdited = YES;
    self.updatedProperty[@"hSpacing"] = @YES;
}

- (uint64_t)vSpacing {
    return _vSpacing;
}

- (void)setVSpacing:(uint64_t)newVSpacing
{
    _vSpacing = newVSpacing;
    self.isEdited = YES;
    self.updatedProperty[@"vSpacing"] = @YES;
}

- (uint8_t)newProfile {
    return _newProfile;
}

- (void)setNewProfile:(uint8_t)newProfile
{
    _newProfile = newProfile;
    self.isEdited = YES;

    if (_newProfile == _origProfile) {
        self.updatedProperty[@"profile"] = @NO;
    }
    else {
        self.updatedProperty[@"profile"] = @YES;
    }
}

- (uint8_t)newLevel {
    return _newLevel;
}

- (void)setNewLevel:(uint8_t)newLevel
{
    _newLevel = newLevel;
    self.isEdited = YES;

    if (_newLevel == _origLevel) {
        self.updatedProperty[@"level"] = @NO;
    }
    else {
        self.updatedProperty[@"level"] = @YES;
    }
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    MP42VideoTrack *copy = [super copyWithZone:zone];

    if (copy) {
        copy->_width = _width;
        copy->_height = _height;
        copy->_trackWidth = _trackWidth;
        copy->_trackHeight = _trackHeight;

        copy->_hSpacing = _hSpacing;
        copy->_vSpacing = _vSpacing;

        copy->_cleanApertureWidthN = _cleanApertureWidthN;
        copy->_cleanApertureWidthD = _cleanApertureWidthD;
        copy->_cleanApertureHeightN = _cleanApertureHeightN;
        copy->_cleanApertureHeightD = _cleanApertureHeightD;
        copy->_horizOffN = _horizOffN;
        copy->_horizOffD = _horizOffD;
        copy->_vertOffN = _vertOffN;
        copy->_vertOffD = _vertOffD;

        copy->_offsetX = _offsetX;
        copy->_offsetY = _offsetY;

        copy->_origLevel = _origLevel;
        copy->_origProfile = _origProfile;
        copy->_newProfile = _newProfile;
        copy->_newLevel = _newLevel;
    }

    return copy;
}

#pragma mark - NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    [coder encodeInt:1 forKey:@"MP42VideoTrackVersion"];

    [coder encodeInt64:_width forKey:@"width"];
    [coder encodeInt64:_height forKey:@"height"];

    [coder encodeFloat:_trackWidth forKey:@"trackWidth"];
    [coder encodeFloat:_trackHeight forKey:@"trackHeight"];

    [coder encodeInt64:_hSpacing forKey:@"hSpacing"];
    [coder encodeInt64:_vSpacing forKey:@"vSpacing"];

    [coder encodeInt32:_offsetX forKey:@"offsetX"];
    [coder encodeInt32:_offsetY forKey:@"offsetY"];

    [coder encodeInt:_origProfile forKey:@"origProfile"];
    [coder encodeInt:_origLevel forKey:@"origLevel"];

    [coder encodeInt:_newProfile forKey:@"newProfile"];
    [coder encodeInt:_newLevel forKey:@"newLevel"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    _width = [decoder decodeInt64ForKey:@"width"];
    _height = [decoder decodeInt64ForKey:@"height"];

    _trackWidth = [decoder decodeFloatForKey:@"trackWidth"];
    _trackHeight = [decoder decodeFloatForKey:@"trackHeight"];

    _hSpacing = [decoder decodeInt64ForKey:@"hSpacing"];
    _vSpacing = [decoder decodeInt64ForKey:@"vSpacing"];

    _offsetX = [decoder decodeInt32ForKey:@"offsetX"];
    _offsetY = [decoder decodeInt32ForKey:@"offsetY"];

    _origProfile = [decoder decodeIntForKey:@"origProfile"];
    _origLevel = [decoder decodeIntForKey:@"origLevel"];

    _newProfile = [decoder decodeIntForKey:@"newProfile"];
    _newLevel = [decoder decodeIntForKey:@"newLevel"];

    return self;
}

- (NSString *)description {
    return [[super description] stringByAppendingFormat:@", %lld x %lld", _width, _height];
}

@end
