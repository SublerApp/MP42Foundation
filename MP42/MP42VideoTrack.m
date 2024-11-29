//
//  MP42VideoTrack.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42VideoTrack.h"
#import "MP42Track+Private.h"
#import "MP42MediaFormat.h"
#import "MP42PrivateUtilities.h"
#import "MP42-Shared-Swift.h"
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

        // Sample descriptions
//        uint32_t count = MP4GetTrackNumberOfSampleDescriptions(fileHandle, self.trackId);
//
//        NSMutableArray<MP42SampleDescription *> *descriptions = [NSMutableArray array];
//        for (uint32_t index = 0; index < count; index++) {
//            MP42VideoSampleDescription *description = [[MP42VideoSampleDescription alloc] initWithFileHandle:fileHandle trackId:self.trackId index:index];
//            [descriptions addObject:description];
//        }
//        self.sampleDescriptions = [descriptions copy];

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

                if (!strcmp(type, "nclx")) {
                    uint64_t colorRange;
                    MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.full_range_flag", &colorRange);
                    _colorRange = (uint16_t)colorRange;
                }
            }
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clli")) {
            uint64_t maxCLL, maxFALL;
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clli.maxContentLightLevel", &maxCLL);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.clli.maxPicAverageLightLevel", &maxFALL);
            _coll.MaxCLL = (unsigned int)maxCLL;
            _coll.MaxFALL = (unsigned int)maxFALL;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv")) {
            uint64_t displayPrimariesGX, displayPrimariesGY, displayPrimariesBX,
                     displayPrimariesBY, displayPrimariesRX, displayPrimariesRY,
                     whitePointX, whitePointY,
                     maxDisplayMasteringLuminance, minDisplayMasteringLuminance;

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.displayPrimariesGX", &displayPrimariesGX);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.displayPrimariesGY", &displayPrimariesGY);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.displayPrimariesBX", &displayPrimariesBX);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.displayPrimariesBY", &displayPrimariesBY);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.displayPrimariesRX", &displayPrimariesRX);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.displayPrimariesRY", &displayPrimariesRY);

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.whitePointX", &whitePointX);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.whitePointY", &whitePointY);

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.maxDisplayMasteringLuminance", &maxDisplayMasteringLuminance);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.mdcv.minDisplayMasteringLuminance", &minDisplayMasteringLuminance);

            const int chromaDen = 50000;
            const int lumaDen = 10000;

            _mastering.display_primaries[0][0] = make_rational((int)displayPrimariesRX,  chromaDen);
            _mastering.display_primaries[0][1] = make_rational((int)displayPrimariesRY,  chromaDen);
            _mastering.display_primaries[1][0] = make_rational((int)displayPrimariesGX,  chromaDen);
            _mastering.display_primaries[1][1] = make_rational((int)displayPrimariesGY,  chromaDen);
            _mastering.display_primaries[2][0] = make_rational((int)displayPrimariesBX,  chromaDen);
            _mastering.display_primaries[2][1] = make_rational((int)displayPrimariesBY,  chromaDen);

            _mastering.white_point[0] = make_rational((int)whitePointX, chromaDen);
            _mastering.white_point[1] = make_rational((int)whitePointY, chromaDen);

            _mastering.max_luminance = make_rational((int)maxDisplayMasteringLuminance, lumaDen);
            _mastering.min_luminance = make_rational((int)minDisplayMasteringLuminance, lumaDen);

            _mastering.has_primaries = 1;
            _mastering.has_luminance = 1;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.amve")) {
            uint64_t ambientIlluminance, ambientLightX, ambientLightY;

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.amve.ambientIlluminance", &ambientIlluminance);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.amve.ambientLightX", &ambientLightX);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.amve.ambientLightY", &ambientLightY);

            _ambient.ambient_illuminance = (uint32_t)ambientIlluminance;
            _ambient.ambient_light_x = ambientLightX;
            _ambient.ambient_light_y = ambientLightY;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC")) {
            uint64_t versionMajor, versionMinor, profile, level, rpuPresentFlag, elPresentFlag, blPresentFlag, blSignalCompatibilityId;

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.dv_version_major", &versionMajor);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.dv_version_minor", &versionMinor);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.dv_profile", &profile);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.dv_level", &level);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.rpu_present_flag", &rpuPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.el_present_flag", &elPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.bl_present_flag", &blPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvcC.dv_bl_signal_compatibility_id", &blSignalCompatibilityId);

            _dolbyVision.versionMajor = versionMajor;
            _dolbyVision.versionMinor = versionMinor;
            _dolbyVision.profile = profile;
            _dolbyVision.level = level;
            _dolbyVision.rpuPresentFlag = rpuPresentFlag;
            _dolbyVision.elPresentFlag = elPresentFlag;
            _dolbyVision.blPresentFlag = blPresentFlag;
            _dolbyVision.blSignalCompatibilityId = blSignalCompatibilityId;
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC")) {
            uint64_t versionMajor, versionMinor, profile, level, rpuPresentFlag, elPresentFlag, blPresentFlag, blSignalCompatibilityId;

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.dv_version_major", &versionMajor);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.dv_version_minor", &versionMinor);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.dv_profile", &profile);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.dv_level", &level);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.rpu_present_flag", &rpuPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.el_present_flag", &elPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.bl_present_flag", &blPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvvC.dv_bl_signal_compatibility_id", &blSignalCompatibilityId);

            _dolbyVision.versionMajor = versionMajor;
            _dolbyVision.versionMinor = versionMinor;
            _dolbyVision.profile = profile;
            _dolbyVision.level = level;
            _dolbyVision.rpuPresentFlag = rpuPresentFlag;
            _dolbyVision.elPresentFlag = elPresentFlag;
            _dolbyVision.blPresentFlag = blPresentFlag;
            _dolbyVision.blSignalCompatibilityId = blSignalCompatibilityId;
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC")) {
            uint64_t versionMajor, versionMinor, profile, level, rpuPresentFlag, elPresentFlag, blPresentFlag, blSignalCompatibilityId;

            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.dv_version_major", &versionMajor);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.dv_version_minor", &versionMinor);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.dv_profile", &profile);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.dv_level", &level);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.rpu_present_flag", &rpuPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.el_present_flag", &elPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.bl_present_flag", &blPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.dvwC.dv_bl_signal_compatibility_id", &blSignalCompatibilityId);

            _dolbyVision.versionMajor = versionMajor;
            _dolbyVision.versionMinor = versionMinor;
            _dolbyVision.profile = profile;
            _dolbyVision.level = level;
            _dolbyVision.rpuPresentFlag = rpuPresentFlag;
            _dolbyVision.elPresentFlag = elPresentFlag;
            _dolbyVision.blPresentFlag = blPresentFlag;
            _dolbyVision.blSignalCompatibilityId = blSignalCompatibilityId;
        }

        if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.hvcE")) {
            uint8_t *ppValue;
            uint32_t pValueSize = 0;
            MP4GetTrackBytesProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.hvcE.HEVCConfig", &ppValue, &pValueSize);
            if (pValueSize) {
                _dolbyVisionELConfiguration = [NSData dataWithBytesNoCopy:ppValue length:pValueSize];
            }
        }
        else if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.avcE")) {
            uint8_t *ppValue;
            uint32_t pValueSize = 0;
            MP4GetTrackBytesProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.avcE.AVCConfig", &ppValue, &pValueSize);
            if (pValueSize) {
                _dolbyVisionELConfiguration = [NSData dataWithBytesNoCopy:ppValue length:pValueSize];
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
        uint32_t *ptr32 = (uint32_t *)nval;
        uint32_t size;

        MP4GetTrackBytesProperty(fileHandle, self.trackId, "tkhd.matrix", &val, &size);
        memcpy(nval, val, size);
        ptr32[0] = convertToFixedPoint(_transform.a);
        ptr32[1] = convertToFixedPoint(_transform.b);
        ptr32[3] = convertToFixedPoint(_transform.c);
        ptr32[4] = convertToFixedPoint(_transform.d);
        ptr32[6] = convertToFixedPoint(_transform.tx);
        ptr32[7] = convertToFixedPoint(_transform.ty);
        MP4SetTrackBytesProperty(fileHandle, self.trackId, "tkhd.matrix", nval, size);

        free(val);

        if ((self.format == kMP42VideoCodecType_H264    || self.format == kMP42VideoCodecType_MPEG4Video
             || self.format == kMP42VideoCodecType_HEVC || self.format == kMP42VideoCodecType_HEVC_PSinBitstream
             || self.format == kMP42VideoCodecType_VVC  || self.format == kMP42VideoCodecType_VVC_PSinBitstream
             || self.format == kMP42VideoCodecType_AV1  || self.format == kMP42VideoCodecType_DolbyVisionHEVC)) {

            if (self.updatedProperty[@"colr"] || self.muxed == NO) {
                if (_colorPrimaries > 0 && _transferCharacteristics > 0 && _matrixCoefficients > 0) {
                    const char *type;
                    if (MP4HaveTrackAtom(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr")) {
                        if (MP4GetTrackStringProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.colorParameterType", &type)) {
                            if (!strcmp(type, "nclc") || !strcmp(type, "nclx")) {
                                MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.primariesIndex", _colorPrimaries);
                                MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.transferFunctionIndex", _transferCharacteristics);
                                MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.matrixIndex", _matrixCoefficients);
                            }
                            if (!strcmp(type, "nclx")) {
                                MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.full_range_flag", _colorRange);
                            }
                        }
                    }
                    else {
                        MP4AddColr(fileHandle, self.trackId, _colorPrimaries, _transferCharacteristics, _matrixCoefficients);
                        MP4SetTrackIntegerProperty(fileHandle, self.trackId, "mdia.minf.stbl.stsd.*.colr.full_range_flag", _colorRange);
                    }
                }
                else {
                    MP4AddColr(fileHandle, self.trackId, 0, 0, 0);
                }
            }

            if (self.updatedProperty[@"coll"] || self.muxed == NO) {
                if (self.coll.MaxCLL > 0 && self.coll.MaxFALL > 0) {
                    MP4SetContentLightMetadata(fileHandle, self.trackId, _coll.MaxCLL, _coll.MaxFALL);
                }
                else {
                    MP4SetContentLightMetadata(fileHandle, self.trackId, 0, 0);
                }
            }

            if (self.updatedProperty[@"mdcv"] || self.muxed == NO) {
                if (self.mastering.has_primaries && self.mastering.has_luminance) {
                    const int chromaDen = 50000;
                    const int lumaDen = 10000;
                    MP4SetMasteringDisplayMetadata(fileHandle, self.trackId,
                                                    mp42_rescale_q(_mastering.display_primaries[1][0], chromaDen),
                                                    mp42_rescale_q(_mastering.display_primaries[1][1], chromaDen),
                                                    mp42_rescale_q(_mastering.display_primaries[2][0], chromaDen),
                                                    mp42_rescale_q(_mastering.display_primaries[2][1], chromaDen),
                                                    mp42_rescale_q(_mastering.display_primaries[0][0], chromaDen),
                                                    mp42_rescale_q(_mastering.display_primaries[0][1], chromaDen),
                                                    mp42_rescale_q(_mastering.white_point[0], chromaDen),
                                                    mp42_rescale_q(_mastering.white_point[1], chromaDen),
                                                    (uint32_t)mp42_rescale_q(_mastering.max_luminance, lumaDen),
                                                    (uint32_t)mp42_rescale_q(_mastering.min_luminance, lumaDen));
                }
                else {
                    MP4SetMasteringDisplayMetadata(fileHandle, self.trackId, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
                }
            }

            if (self.updatedProperty[@"amve"] || self.muxed == NO) {
                if (self.ambient.ambient_illuminance && self.ambient.ambient_light_x && self.ambient.ambient_light_y) {
                    MP4SetAmbientViewingEnvironment(fileHandle, self.trackId,
                                                   _ambient.ambient_illuminance, _ambient.ambient_light_x, _ambient.ambient_light_y);
                }
                else {
                    MP4SetAmbientViewingEnvironment(fileHandle, self.trackId, 0, 0, 0);
                }
            }

            if (self.updatedProperty[@"hSpacing"] || self.updatedProperty[@"vSpacing"] || self.muxed == NO) {
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
                else {
                    MP4AddCleanAperture(fileHandle, self.trackId,
                                        (uint32_t)_cleanApertureWidthN, (uint32_t)_cleanApertureWidthD,
                                        (uint32_t)_cleanApertureHeightN, (uint32_t)_cleanApertureHeightD,
                                        (uint32_t)_horizOffN, (uint32_t)_horizOffD, (uint32_t)_vertOffN, (uint32_t)_vertOffD);
                }
            }
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

- (void)setColorRange:(uint16_t)colorRange
{
    self.updatedProperty[@"colr"] = @YES;
    _colorRange = colorRange;
    self.edited = YES;
}

- (void)setMastering:(MP42MasteringDisplayMetadata)mastering
{
    self.updatedProperty[@"mdcv"] = @YES;
    _mastering = mastering;
    self.edited = YES;
}

- (void)setColl:(MP42ContentLightMetadata)coll
{
    self.updatedProperty[@"coll"] = @YES;
    _coll = coll;
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

- (NSString *)formatSummary
{
    NSMutableString *summary = [super.formatSummary mutableCopy];
    if (_mastering.has_luminance && _mastering.has_primaries) {
        [summary appendString:@" HDR10"];
    }
    if (_dolbyVision.versionMajor) {
        if (![summary containsString:@"Dolby Vision"]) {
            [summary appendString:@" Dolby Vision"];
        }
        [summary appendFormat:@" %d.%d", _dolbyVision.profile, _dolbyVision.blSignalCompatibilityId];
    }
    return summary;
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
        copy->_colorRange = _colorRange;

        copy->_mastering = _mastering;
        copy->_coll = _coll;
        copy->_dolbyVision = _dolbyVision;
        copy->_dolbyVisionELConfiguration = _dolbyVisionELConfiguration;

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
    [coder encodeInt32:_colorRange forKey:@"colorRange"];

    [coder encodeInt32:_mastering.display_primaries[0][0].num forKey:@"displayPrimaries00Num"];
    [coder encodeInt32:_mastering.display_primaries[0][0].den forKey:@"displayPrimaries00Den"];
    [coder encodeInt32:_mastering.display_primaries[0][1].num forKey:@"displayPrimaries01Num"];
    [coder encodeInt32:_mastering.display_primaries[0][1].den forKey:@"displayPrimaries01Den"];

    [coder encodeInt32:_mastering.display_primaries[1][0].num forKey:@"displayPrimaries10Num"];
    [coder encodeInt32:_mastering.display_primaries[1][0].den forKey:@"displayPrimaries10Den"];
    [coder encodeInt32:_mastering.display_primaries[1][1].num forKey:@"displayPrimaries11Num"];
    [coder encodeInt32:_mastering.display_primaries[1][1].den forKey:@"displayPrimaries11Den"];

    [coder encodeInt32:_mastering.display_primaries[2][0].num forKey:@"displayPrimaries20Num"];
    [coder encodeInt32:_mastering.display_primaries[2][0].den forKey:@"displayPrimaries20Den"];
    [coder encodeInt32:_mastering.display_primaries[2][1].num forKey:@"displayPrimaries21Num"];
    [coder encodeInt32:_mastering.display_primaries[2][1].den forKey:@"displayPrimaries21Den"];

    [coder encodeInt32:_mastering.white_point[0].num forKey:@"whitePoint0Num"];
    [coder encodeInt32:_mastering.white_point[0].den forKey:@"whitePoint0Den"];
    [coder encodeInt32:_mastering.white_point[1].num forKey:@"whitePoint1Num"];
    [coder encodeInt32:_mastering.white_point[1].den forKey:@"whitePoint1Den"];

    [coder encodeInt32:_mastering.has_primaries forKey:@"hasPrimaries"];
    [coder encodeInt32:_mastering.has_luminance forKey:@"hasLuminance"];

    [coder encodeInt64:_coll.MaxCLL forKey:@"maxCLL"];
    [coder encodeInt64:_coll.MaxFALL forKey:@"maxFALL"];

    [coder encodeInt64:_hSpacing forKey:@"hSpacing"];
    [coder encodeInt64:_vSpacing forKey:@"vSpacing"];

    [coder encodeInt32:_dolbyVision.versionMajor forKey:@"DVversionMajor"];
    [coder encodeInt32:_dolbyVision.versionMinor forKey:@"DVversionMinor"];
    [coder encodeInt32:_dolbyVision.profile forKey:@"DVprofile"];
    [coder encodeInt32:_dolbyVision.level forKey:@"DVlevel"];
    [coder encodeInt32:_dolbyVision.rpuPresentFlag forKey:@"DVrpuPresentFlag"];
    [coder encodeInt32:_dolbyVision.elPresentFlag forKey:@"DVelPresentFlag"];
    [coder encodeInt32:_dolbyVision.blPresentFlag forKey:@"DVblPresentFlag"];
    [coder encodeInt32:_dolbyVision.blSignalCompatibilityId forKey:@"DVblSignalCompatibilityId"];
    [coder encodeObject:_dolbyVisionELConfiguration forKey:@"DVELConfiguration"];

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
        _colorRange = (uint16_t)[decoder decodeInt32ForKey:@"colorRange"];

        _mastering.display_primaries[0][0].num = [decoder decodeInt32ForKey:@"displayPrimaries00Num"];
        _mastering.display_primaries[0][0].den = [decoder decodeInt32ForKey:@"displayPrimaries00Den"];
        _mastering.display_primaries[0][1].num = [decoder decodeInt32ForKey:@"displayPrimaries01Num"];
        _mastering.display_primaries[0][1].den = [decoder decodeInt32ForKey:@"displayPrimaries01Den"];

        _mastering.display_primaries[1][0].num = [decoder decodeInt32ForKey:@"displayPrimaries10Num"];
        _mastering.display_primaries[1][0].den = [decoder decodeInt32ForKey:@"displayPrimaries10Den"];
        _mastering.display_primaries[1][1].num = [decoder decodeInt32ForKey:@"displayPrimaries11Num"];
        _mastering.display_primaries[1][1].den = [decoder decodeInt32ForKey:@"displayPrimaries11Den"];

        _mastering.display_primaries[2][0].num = [decoder decodeInt32ForKey:@"displayPrimaries20Num"];
        _mastering.display_primaries[2][0].den = [decoder decodeInt32ForKey:@"displayPrimaries20Den"];
        _mastering.display_primaries[2][1].num = [decoder decodeInt32ForKey:@"displayPrimaries21Num"];
        _mastering.display_primaries[2][1].den = [decoder decodeInt32ForKey:@"displayPrimaries21Den"];

        _mastering.white_point[0].num = [decoder decodeInt32ForKey:@"whitePoint0Num"];
        _mastering.white_point[0].den = [decoder decodeInt32ForKey:@"whitePoint0Den"];
        _mastering.white_point[1].num = [decoder decodeInt32ForKey:@"whitePoint1Num"];
        _mastering.white_point[1].den = [decoder decodeInt32ForKey:@"whitePoint1Den"];

        _mastering.has_primaries = [decoder decodeInt32ForKey:@"hasPrimaries"] > 0;
        _mastering.has_luminance = [decoder decodeInt32ForKey:@"hasLuminance"] > 0;

        _coll.MaxCLL = (uint32_t)[decoder decodeInt64ForKey:@"maxCLL"];
        _coll.MaxFALL = (uint32_t)[decoder decodeInt64ForKey:@"maxFALL"];

        _dolbyVision.versionMajor = [decoder decodeInt32ForKey:@"DVversionMajor"];
        _dolbyVision.versionMinor = [decoder decodeInt32ForKey:@"DVversionMinor"];
        _dolbyVision.profile      = [decoder decodeInt32ForKey:@"DVprofile"];
        _dolbyVision.level        = [decoder decodeInt32ForKey:@"DVlevel"];
        _dolbyVision.rpuPresentFlag = [decoder decodeInt32ForKey:@"DVrpuPresentFlag"];
        _dolbyVision.elPresentFlag  = [decoder decodeInt32ForKey:@"DVelPresentFlag"];
        _dolbyVision.blPresentFlag  = [decoder decodeInt32ForKey:@"DVblPresentFlag"];
        _dolbyVision.blSignalCompatibilityId = [decoder decodeInt32ForKey:@"DVblSignalCompatibilityId"];
        _dolbyVisionELConfiguration = [decoder decodeObjectOfClass:[NSData class] forKey:@"DVELConfiguration"];

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
    return [super.description stringByAppendingFormat:@", %lld x %lld", _width, _height];
}

@end
