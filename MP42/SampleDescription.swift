//
//  SamplerDescription.swift
//  MP42Foundation
//
//  Created by Damiano Galassi on 12/12/21.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

import Foundation
import CMP42

@objc(MP42SampleDescription) public class SampleDescription: NSObject {
    let format: MP42CodecType

    @objc public init(fileHandle: MP42FileHandle, trackId: MP42TrackId, index: UInt32) {
        let type = String(cString: MP4GetTrackType(fileHandle, trackId))
        let mediaDataName = String(cString: MP4GetTrackMediaDataName(fileHandle, trackId, index))

        switch (type, mediaDataName) {
        case (_, "twos"):
            format = kMP42AudioCodecType_LinearPCM
        case (_, "mp4a"):
            let typeId = Int32(MP4GetTrackEsdsObjectTypeId(fileHandle, trackId))
            switch typeId {
            case MP4_MPEG4_AUDIO_TYPE:
                format = kMP42AudioCodecType_MPEG4AAC
            case MP4_MPEG2_AUDIO_TYPE, MP4_MPEG1_AUDIO_TYPE:
                format = kMP42AudioCodecType_MPEGLayer3
            case 0xA9:
                format = kMP42AudioCodecType_DTS
            default:
                format = kMP42MediaType_Unknown
            }
        case ("subp", "mp4s"):
            format = kMP42SubtitleCodecType_VobSub
        case (_, _):
            format = FourCharCode(mediaDataName)
        }
    }
}

struct Size {
    var width: UInt16
    var height: UInt16
}

struct ColorInfo {
    var colorPrimaries: UInt16
    var transferCharacteristics: UInt16
    var matrixCoefficients: UInt16
    var colorRange: UInt16
}

struct PixelAspectRatio {
    var hSpacing: UInt64
    var vSpacing: UInt64
}

struct CleanAperture {
    var widthN: UInt64
    var widthD: UInt64
    var heightN: UInt64
    var heightD: UInt64
    var horizOffN: UInt64
    var horizOffD: UInt64
    var vertOffN: UInt64
    var vertOffD: UInt64
}

struct H264Profile {
    var origProfile: UInt8
    var origLevel: UInt8
    var newProfile: UInt8
    var newLevel: UInt8
}

@objc(MP42VideoSampleDescription) public class VideoSampleDescription: SampleDescription {
    var size: Size
    var color: ColorInfo?
    var mastering: MP42MasteringDisplayMetadata?
    var coll: MP42ContentLightMetadata?
    var dolbyVision: MP42DolbyVisionMetadata?
    var pasp: PixelAspectRatio
    var cleanAperture: CleanAperture?
    var profile: H264Profile?

    @objc public override init(fileHandle: MP42FileHandle, trackId: MP42TrackId, index: UInt32) {
        let width = MP4GetTrackVideoWidth(fileHandle, trackId)
        let height = MP4GetTrackVideoHeight(fileHandle, trackId)

        self.size = Size(width: width, height: height)

        // Color Information

//        if MP4HaveTrackAtom(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].colr") {
//            var colorPrimaries: UInt64 = 0, transferCharacteristics: UInt64 = 0, matrixCoefficients: UInt64 = 0, colorRange: UInt = 0
//
//            var atomType = "nclc"
//            //if (MP4GetTrackStringProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.*.colr.colorParameterType", &atomType))
//
//            self.color = ColorInfo(colorPrimaries: UInt16(colorPrimaries), transferCharacteristics: UInt16(transferCharacteristics), matrixCoefficients: UInt16(matrixCoefficients), colorRange: UInt16(colorRange))
//        }

        // Pixel aspect ratio

        var hSpacing: UInt64 = 1, vSpacing: UInt64 = 1

        if MP4HaveTrackAtom(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].pasp") != 0 {
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].pasp.hSpacing", &hSpacing)
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].pasp.vSpacing", &vSpacing)
        }

        self.pasp = PixelAspectRatio(hSpacing: hSpacing, vSpacing: vSpacing)

        // Content light level

        if MP4HaveTrackAtom(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clli") != 0 {
            var maxCLL: UInt64 = 0, maxFALL: UInt64 = 0

            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clli.maxContentLightLevel", &maxCLL)
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clli.maxPicAverageLightLevel", &maxFALL)

            self.coll = MP42ContentLightMetadata(MaxCLL: UInt32(maxCLL), MaxFALL: UInt32(maxFALL))
        }

        // Mastering display metadata

        if MP4HaveTrackAtom(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv") != 0 {
            var displayPrimariesGX: UInt64 = 0, displayPrimariesGY: UInt64 = 0, displayPrimariesBX: UInt64 = 0,
                displayPrimariesBY: UInt64 = 0, displayPrimariesRX: UInt64 = 0, displayPrimariesRY: UInt64 = 0,
                whitePointX: UInt64 = 0, whitePointY: UInt64 = 0,
                maxDisplayMasteringLuminance: UInt64 = 0, minDisplayMasteringLuminance: UInt64 = 0;

            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.displayPrimariesGX", &displayPrimariesGX);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.displayPrimariesGY", &displayPrimariesGY);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.displayPrimariesBX", &displayPrimariesBX);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.displayPrimariesBY", &displayPrimariesBY);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.displayPrimariesRX", &displayPrimariesRX);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.displayPrimariesRY", &displayPrimariesRY);

            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.whitePointX", &whitePointX);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.whitePointY", &whitePointY);

            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.maxDisplayMasteringLuminance", &maxDisplayMasteringLuminance);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].mdcv.minDisplayMasteringLuminance", &minDisplayMasteringLuminance);

            let chromaDen: Int32 = 50000, lumaDen: Int32 = 10000;

            self.mastering = MP42MasteringDisplayMetadata(display_primaries: ((make_rational(Int32(displayPrimariesRX), chromaDen),
                                                                               make_rational(Int32(displayPrimariesRY), chromaDen)),
                                                                              (make_rational(Int32(displayPrimariesGX), chromaDen),
                                                                               make_rational(Int32(displayPrimariesGY), chromaDen)),
                                                                              (make_rational(Int32(displayPrimariesBX), chromaDen),
                                                                               make_rational(Int32(displayPrimariesBY), chromaDen))),
                                                          white_point: (make_rational(Int32(whitePointX), chromaDen),
                                                                        make_rational(Int32(whitePointY), chromaDen)),
                                                          min_luminance: make_rational(Int32(minDisplayMasteringLuminance), lumaDen),
                                                          max_luminance: make_rational(Int32(maxDisplayMasteringLuminance), lumaDen),
                                                          has_primaries: 1,
                                                          has_luminance: 1)
        }

        // Dolby Vision Configuration

        if MP4HaveTrackAtom(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvcC") != 0 {
            var versionMajor: UInt64 = 0, versionMinor: UInt64 = 0, profile: UInt64 = 0,
                level: UInt64 = 0, rpuPresentFlag: UInt64 = 0, elPresentFlag: UInt64 = 0,
                blPresentFlag: UInt64 = 0, blSignalCompatibilityId: UInt64 = 0;

            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.dv_version_major", &versionMajor);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.dv_version_minor", &versionMinor);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.dv_profile", &profile);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.dv_level", &level);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.rpu_present_flag", &rpuPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.el_present_flag", &elPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.bl_present_flag", &blPresentFlag);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].dvvC.dv_bl_signal_compatibility_id", &blSignalCompatibilityId);

            self.dolbyVision = MP42DolbyVisionMetadata(versionMajor: UInt8(versionMajor), versionMinor: UInt8(versionMinor),
                                                       profile: UInt8(profile), level: UInt8(level),
                                                       rpuPresentFlag: (rpuPresentFlag != 0), elPresentFlag: (elPresentFlag != 0),
                                                       blPresentFlag: (blPresentFlag != 0), blSignalCompatibilityId: UInt8(blSignalCompatibilityId))
        }

        // Clean aperture
        if MP4HaveTrackAtom(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap") != 0 {
            var widthN: UInt64 = 0, widthD: UInt64 = 0,
                heightN: UInt64 = 0, heightD: UInt64 = 0,
                horizOffN: UInt64 = 0, horizOffD: UInt64 = 0,
                vertOffN: UInt64 = 0, vertOffD: UInt64 = 0;

            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.cleanApertureWidthN", &widthN);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.cleanApertureWidthD", &widthD);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.cleanApertureHeightN", &heightN);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.cleanApertureHeightD", &heightD);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.horizOffN", &horizOffN);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.horizOffD", &horizOffD);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.vertOffN", &vertOffN);
            MP4GetTrackIntegerProperty(fileHandle, trackId, "mdia.minf.stbl.stsd.[\(index)].clap.vertOffD", &vertOffD);

            self.cleanAperture = CleanAperture(widthN: widthN, widthD: widthD, heightN: heightN, heightD: heightD,
                                               horizOffN: horizOffN, horizOffD: horizOffD, vertOffN: vertOffN, vertOffD: vertOffD)

        }

        super.init(fileHandle: fileHandle, trackId: trackId, index: index)

        if format == kMP42VideoCodecType_H264 {
            var origProfile: UInt8 = 0, origLevel: UInt8 = 0
            MP4GetTrackH264ProfileLevel(fileHandle, trackId,
                                        &origProfile, &origLevel)
            self.profile = H264Profile(origProfile: origProfile,origLevel: origLevel,
                                       newProfile: origProfile, newLevel: origLevel)
        }
    }
}

class AudioSampleDescription: SampleDescription {
    var channels: UInt32
    var channelLayoutTag: UInt32
    var extensionType: MP42AudioEmbeddedExtension

    override init(fileHandle: MP42FileHandle, trackId: MP42TrackId,index: UInt32) {
        self.channels = 0
        self.channelLayoutTag = 0
        self.extensionType = kMP42AudioEmbeddedExtension_None

        super.init(fileHandle: fileHandle, trackId: trackId, index: index)
    }

}


/**
 Set FourCharCode/OSType using a String.

 Examples:
 let test: FourCharCode = "420v"
 let test2 = FourCharCode("420f")
 print(test.string, test2.string)
*/
extension UInt32: @retroactive ExpressibleByExtendedGraphemeClusterLiteral {}
extension UInt32: @retroactive ExpressibleByUnicodeScalarLiteral {}
extension FourCharCode: @retroactive ExpressibleByStringLiteral {

    public init(stringLiteral value: StringLiteralType) {
        var code: FourCharCode = 0
        // Value has to consist of 4 printable ASCII characters, e.g. '420v'.
        // Note: This implementation does not enforce printable range (32-126)
        if value.count == 4 && value.utf8.count == 4 {
            for byte in value.utf8 {
                code = code << 8 + FourCharCode(byte)
            }
        }
        else {
            print("FourCharCode: Can't initialize with '\(value)', only printable ASCII allowed. Setting to '????'.")
            code = 0x3F3F3F3F // = '????'
        }
        self = code
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self = FourCharCode(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self = FourCharCode(stringLiteral: value)
    }

    public init(_ value: String) {
        self = FourCharCode(stringLiteral: value)
    }

    public var string: String? {
        let cString: [CChar] = [
            CChar(self >> 24 & 0xFF),
            CChar(self >> 16 & 0xFF),
            CChar(self >> 8 & 0xFF),
            CChar(self & 0xFF),
            0
        ]
        return String(cString: cString)
    }
}
