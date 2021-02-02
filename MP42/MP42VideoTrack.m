//
//  MP42VideoTrack.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2021 Damiano Galassi. All rights reserved.
//

#import "MP42VideoTrack.h"
#import "MP42Track+Private.h"
#import "MP42MediaFormat.h"
#import "MP42PrivateUtilities.h"
#import <mp4v2.h>

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42VideoTrack

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(MP42TrackId)trackID fileHandle:(MP42FileHandle)fileHandle
{
    self = [super initWithSourceURL:URL trackID:trackID fileHandle:fileHandle];

    if (self) {

        if ([self isMemberOfClass:[MP42VideoTrack class]]) {
            _height = MP4GetTrackVideoHeight(fileHandle, self.trackId);
            _width = MP4GetTrackVideoWidth(fileHandle, self.trackId);
        }

        MP4GetTrackFloatProperty(fileHandle, self.trackId, "tkhd.width", &_trackWidth);
        MP4GetTrackFloatProperty(fileHandle, self.trackId, "tkhd.height", &_trackHeight);

        _transform = CGAffineTransformIdentity;
        
        uint8_t *val;
        uint8_t nval[36];
        uint32_t *ptr32 = (uint32_t*) nval;
        uint32_t size;

        MP4GetTrackBytesProperty(fileHandle ,self.trackId, "tkhd.matrix", &val, &size);
        memcpy(nval, val, size);
        _transform.a = CFSwapInt32BigToHost(ptr32[0]) / 0x10000;
        _transform.b = CFSwapInt32BigToHost(ptr32[1]) / 0x10000;
        _transform.c = CFSwapInt32BigToHost(ptr32[3]) / 0x10000;
        _transform.d = CFSwapInt32BigToHost(ptr32[4]) / 0x10000;
        _transform.tx = CFSwapInt32BigToHost(ptr32[6]) / 0x10000;
        _transform.ty = CFSwapInt32BigToHost(ptr32[7]) / 0x10000;
        free(val);

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp")) {
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp.hSpacing", &_hSpacing);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.pasp.vSpacing", &_vSpacing);
        }
        else {
            _hSpacing = 1;
            _vSpacing = 1;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr")) {
            const char *type;
            if (MP4GetTrackStringProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.colorParameterType", &type)) {
                if (!strcmp(type, "nclc") || !strcmp(type, "nclx")) {
                    uint64_t colorPrimaries, transferCharacteristics, matrixCoefficients;

                    MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.primariesIndex", &colorPrimaries);
                    MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.transferFunctionIndex", &transferCharacteristics);
                    MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.matrixIndex", &matrixCoefficients);

                    _colorPrimaries = (uint16_t)colorPrimaries;
                    _transferCharacteristics = (uint16_t)transferCharacteristics;
                    _matrixCoefficients = (uint16_t)matrixCoefficients;
                }
            }
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
    self = [super init];
    if (self) {
        self.mediaType = kMP42MediaType_Video;
        _transform = CGAffineTransformIdentity;
    }
    return self;
}

static uint32_t convertToFixedPoint(CGFloat value) {
    uint32_t fixedValue = 0;
#ifdef __arm64
    if (value < 0) {
        fixedValue = UINT32_MAX - UINT16_MAX * (value * -1);
    } else {
#endif
        fixedValue = value * 0x10000;
#ifdef __arm64
    }
#endif
    return CFSwapInt32HostToBig(fixedValue);
}

- (BOOL)writeToFile:(MP4FileHandle)fileHandle error:(NSError * __autoreleasing *)outError __attribute__((no_sanitize("float-cast-overflow")))
{
    if (!fileHandle || !self.trackId || ![super writeToFile:fileHandle error:outError]) {
        if (outError != NULL) {
            *outError = MP42Error(MP42LocalizedString(@"Error: couldn't mux video track", @"error message"),
                                  nil,
                                  120);
            return NO;
        }
    }

    if (_trackWidth > 0 && _trackHeight > 0) {
        MP4SetTrackFloatProperty(fileHandle, self.trackId, "tkhd.width", _trackWidth);
        MP4SetTrackFloatProperty(fileHandle, self.trackId, "tkhd.height", _trackHeight);

        uint8_t *val;
        uint8_t nval[36];
        uint32_t *ptr32 = (uint32_t *) nval;
        uint32_t size;

        MP4GetTrackBytesProperty(fileHandle ,self.trackId, "tkhd.matrix", &val, &size);
        memcpy(nval, val, size);
        ptr32[0] = convertToFixedPoint(_transform.a);
        ptr32[1] = convertToFixedPoint(_transform.b);
        ptr32[3] = convertToFixedPoint(_transform.c);
        ptr32[4] = convertToFixedPoint(_transform.d);
        ptr32[6] = convertToFixedPoint(_transform.tx);
        ptr32[7] = convertToFixedPoint(_transform.ty);
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

        if (self.updatedProperty[@"colr"] &&
            (self.format == kMP42VideoCodecType_H264 || self.format == kMP42VideoCodecType_MPEG4Video
             || self.format == kMP42VideoCodecType_HEVC || self.format == kMP42VideoCodecType_HEVC_PSinBitstream)) {

                if (_colorPrimaries > 0 && _transferCharacteristics > 0 && _matrixCoefficients > 0) {
                    const char *type;
                    if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr")) {
                        if (MP4GetTrackStringProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.colorParameterType", &type)) {
                            if (!strcmp(type, "nclc") || !strcmp(type, "nclx")) {
                                MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.primariesIndex", _colorPrimaries);
                                MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.transferFunctionIndex", _transferCharacteristics);
                                MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.matrixIndex", _matrixCoefficients);
                            }
                        }
                    }
                    else {
                        MP4AddColr(fileHandle, self.trackId, _colorPrimaries, _transferCharacteristics, _matrixCoefficients);
                    }
                }
                else {
                    MP4AddColr(fileHandle, self.trackId, 0, 0, 0);
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
                MP4AddCleanAperture(fileHandle, self.trackId,
                                    (uint32_t)_cleanApertureWidthN, (uint32_t)_cleanApertureWidthD,
                                    (uint32_t)_cleanApertureHeightN, (uint32_t)_cleanApertureHeightD,
                                    (uint32_t)_horizOffN, (uint32_t)_horizOffD, (uint32_t)_vertOffN, (uint32_t)_vertOffD);
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

    return YES;
}

- (void)setTrackWidth:(float)trackWidth
{
    _trackWidth = trackWidth;
    self.edited = YES;
}

- (void)setTrackHeight:(float)trackHeight
{
    _trackHeight = trackHeight;
    self.edited = YES;
}

- (void)setTransform:(CGAffineTransform)transform
{
    _transform = transform;
    self.edited = YES;
}

- (void)setColorPrimaries:(uint16_t)colorPrimaries
{
    self.updatedProperty[@"colr"] = @YES;
    _colorPrimaries = colorPrimaries;
    self.edited = YES;
}

- (void)setTransferCharacteristics:(uint16_t)transferCharacteristics
{
    self.updatedProperty[@"colr"] = @YES;
    _transferCharacteristics = transferCharacteristics;
    self.edited = YES;
}

- (void)setMatrixCoefficients:(uint16_t)matrixCoefficients
{
    self.updatedProperty[@"colr"] = @YES;
    _matrixCoefficients = matrixCoefficients;
    self.edited = YES;
}

- (void)setHSpacing:(uint64_t)newHSpacing
{
    _hSpacing = newHSpacing;
    self.edited = YES;
    self.updatedProperty[@"hSpacing"] = @YES;
}

- (void)setVSpacing:(uint64_t)newVSpacing
{
    _vSpacing = newVSpacing;
    self.edited = YES;
    self.updatedProperty[@"vSpacing"] = @YES;
}

- (void)setNewProfile:(uint8_t)newProfile
{
    _newProfile = newProfile;
    self.edited = YES;

    if (_newProfile == _origProfile) {
        self.updatedProperty[@"profile"] = @NO;
    }
    else {
        self.updatedProperty[@"profile"] = @YES;
    }
}

- (void)setNewLevel:(uint8_t)newLevel
{
    _newLevel = newLevel;
    self.edited = YES;

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
        
        copy->_transform = _transform;

        copy->_colorPrimaries = _colorPrimaries;
        copy->_transferCharacteristics = _transferCharacteristics;
        copy->_matrixCoefficients = _matrixCoefficients;

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

        copy->_origLevel = _origLevel;
        copy->_origProfile = _origProfile;
        copy->_newProfile = _newProfile;
        copy->_newLevel = _newLevel;
    }

    return copy;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    [coder encodeInt:1 forKey:@"MP42VideoTrackVersion"];

    [coder encodeInt64:_width forKey:@"width"];
    [coder encodeInt64:_height forKey:@"height"];

    [coder encodeFloat:_trackWidth forKey:@"trackWidth"];
    [coder encodeFloat:_trackHeight forKey:@"trackHeight"];

    [coder encodeInt32:_colorPrimaries forKey:@"colorPrimaries"];
    [coder encodeInt32:_transferCharacteristics forKey:@"transferCharacteristics"];
    [coder encodeInt32:_matrixCoefficients forKey:@"matrixCoefficients"];

    [coder encodeInt64:_hSpacing forKey:@"hSpacing"];
    [coder encodeInt64:_vSpacing forKey:@"vSpacing"];

    [coder encodeDouble:_transform.a forKey:@"transformA"];
    [coder encodeDouble:_transform.b forKey:@"transformB"];
    [coder encodeDouble:_transform.c forKey:@"transformC"];
    [coder encodeDouble:_transform.d forKey:@"transformD"];
    [coder encodeDouble:_transform.tx forKey:@"offsetX"];
    [coder encodeDouble:_transform.ty forKey:@"offsetY"];

    [coder encodeInt:_origProfile forKey:@"origProfile"];
    [coder encodeInt:_origLevel forKey:@"origLevel"];

    [coder encodeInt:_newProfile forKey:@"newProfile"];
    [coder encodeInt:_newLevel forKey:@"newLevel"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    if (self) {
        _width = [decoder decodeInt64ForKey:@"width"];
        _height = [decoder decodeInt64ForKey:@"height"];

        _trackWidth = [decoder decodeFloatForKey:@"trackWidth"];
        _trackHeight = [decoder decodeFloatForKey:@"trackHeight"];

        _colorPrimaries = (uint16_t)[decoder decodeInt32ForKey:@"colorPrimaries"];
        _transferCharacteristics = (uint16_t)[decoder decodeInt32ForKey:@"transferCharacteristics"];
        _matrixCoefficients = (uint16_t)[decoder decodeInt32ForKey:@"matrixCoefficients"];

        _hSpacing = [decoder decodeInt64ForKey:@"hSpacing"];
        _vSpacing = [decoder decodeInt64ForKey:@"vSpacing"];

        _transform.a = [decoder decodeDoubleForKey:@"transformA"];
        _transform.b = [decoder decodeDoubleForKey:@"transformB"];
        _transform.c = [decoder decodeDoubleForKey:@"transformC"];
        _transform.d = [decoder decodeDoubleForKey:@"transformD"];
        _transform.tx = [decoder decodeDoubleForKey:@"offsetX"];
        _transform.ty = [decoder decodeDoubleForKey:@"offsetY"];

        _origProfile = (uint8_t)[decoder decodeIntForKey:@"origProfile"];
        _origLevel = (uint8_t)[decoder decodeIntForKey:@"origLevel"];

        _newProfile = (uint8_t)[decoder decodeIntForKey:@"newProfile"];
        _newLevel = (uint8_t)[decoder decodeIntForKey:@"newLevel"];
    }

    return self;
}

- (NSString *)description {
    return [[super description] stringByAppendingFormat:@", %lld x %lld", _width, _height];
}

@end
