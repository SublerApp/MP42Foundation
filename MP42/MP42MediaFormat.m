//
//  MP42MediaFormat.h
//  Subler
//
//  Created by Damiano Galassi on 08/08/13.
//
//

#import "MP42MediaFormat.h"
#import "MP42File.h"

// File Type
NSString *const MP42FileTypeMP4 = @"mp4";
NSString *const MP42FileTypeM4V = @"m4v";
NSString *const MP42FileTypeM4A = @"m4a";
NSString *const MP42FileTypeM4B = @"m4b";
NSString *const MP42FileTypeM4R = @"m4r";

// Audio Downmixes
NSString * const SBNoneMixdown = @"SBNoneMixdown";
NSString * const SBMonoMixdown = @"SBMonoMixdown";
NSString * const SBStereoMixdown = @"SBStereoMixdown";
NSString * const SBDolbyMixdown = @"SBDolbyMixdown";
NSString * const SBDolbyPlIIMixdown = @"SBDolbyPlIIMixdown";

NSString *localizedMediaDisplayName(FourCharCode mediaType)
{
    NSString *result = @(FourCC2Str(mediaType));
    NSBundle *bundle = [NSBundle bundleForClass:[MP42File class]];

    switch (mediaType) {
        case kMP42MediaType_Video:
            result = NSLocalizedStringFromTableInBundle(@"Video Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_Audio:
            result = NSLocalizedStringFromTableInBundle(@"Sound Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_Muxed:
            result = NSLocalizedStringFromTableInBundle(@"Muxed Track", @"Localizable", bundle, nil);;
            break;

        case kMP42MediaType_Text:
            result = NSLocalizedStringFromTableInBundle(@"Text Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_ClosedCaption:
            result = NSLocalizedStringFromTableInBundle(@"Closed Caption Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_Subtitle:
        case kMP42MediaType_Subpic:
            result = NSLocalizedStringFromTableInBundle(@"Subtitle Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_TimeCode:
            result = NSLocalizedStringFromTableInBundle(@"TimeCode Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_Metadata:
            result = NSLocalizedStringFromTableInBundle(@"Metadata Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_OD:
            result = NSLocalizedStringFromTableInBundle(@"MPEG-4 ODSM Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_Scene:
            result = NSLocalizedStringFromTableInBundle(@"MPEG-4 SDSM Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_Control:
            result = NSLocalizedStringFromTableInBundle(@"MPEG-4 Control Track", @"Localizable", bundle, nil);
            break;

        case kMP42MediaType_Hint:
            result = NSLocalizedStringFromTableInBundle(@"Hint Track", @"Localizable", bundle, nil);
            break;

        default:
            break;
    }
    
    return result;
}

NSString *localizedVideoDisplayName(FourCharCode mediaSubtype)
{
    NSString *result = @(FourCC2Str(mediaSubtype));

    switch (mediaSubtype) {
        case kMP42VideoCodecType_Animation:
            result = NSLocalizedString(@"Animation", nil);
            break;

        case kMP42VideoCodecType_Cinepak:
            result = NSLocalizedString(@"Cinepak", nil);
            break;

        case kMP42VideoCodecType_JPEG:
            result = NSLocalizedString(@"JPEG", nil);
            break;

        case kMP42VideoCodecType_JPEG_OpenDML:
            result = NSLocalizedString(@"JPEG OpenDML", nil);
            break;

        case kMP42VideoCodecType_PNG:
            result = NSLocalizedString(@"PNG", nil);
            break;

        case kMP42VideoCodecType_H263:
            result = NSLocalizedString(@"H.263", nil);
            break;

        case kMP42VideoCodecType_H264:
            result = NSLocalizedString(@"H.264", nil);
            break;

        case kMP42VideoCodecType_H264_PSinBitstream:
            result = NSLocalizedString(@"H.264 (Parameter Sets in Bitstream)", nil);
            break;

        case kMP42VideoCodecType_DolbyVisionH264:
            result = NSLocalizedString(@"Dolby Vision H.264", nil);
            break;

        case kMP42VideoCodecType_DolbyVisionH264__PSinBitstream:
            result = NSLocalizedString(@"Dolby Vision H.264 (Parameter Sets in Bitstream)", nil);
            break;

        case kMP42VideoCodecType_HEVC:
            result = NSLocalizedString(@"HEVC", nil);
            break;

        case kMP42VideoCodecType_HEVC_PSinBitstream:
            result = NSLocalizedString(@"HEVC (Parameter Sets in Bitstream)", nil);
            break;

        case kMP42VideoCodecType_DolbyVisionHEVC:
            result = NSLocalizedString(@"Dolby Vision HEVC", nil);
            break;

        case kMP42VideoCodecType_DolbyVisionHEVC_PSinBitstream:
            result = NSLocalizedString(@"Dolby Vision HEVC (Parameter Sets in Bitstream)", nil);
            break;

        case kMP42VideoCodecType_VVC:
            result = NSLocalizedString(@"VVC", nil);
            break;

        case kMP42VideoCodecType_VVC_PSinBitstream:
            result = NSLocalizedString(@"VVC (Parameter Sets in Bitstream)", nil);
            break;

        case kMP42VideoCodecType_MPEG4Video:
            result = NSLocalizedString(@"MPEG-4 Visual", nil);
            break;

        case kMP42VideoCodecType_MPEG2Video:
            result = NSLocalizedString(@"MPEG-2 Video", nil);
            break;

        case kMP42VideoCodecType_MPEG1Video:
            result = NSLocalizedString(@"MPEG-1 Video", nil);
            break;

        case kMP42VideoCodecType_SorensonVideo:
            result = NSLocalizedString(@"Sorenson Video", nil);
            break;

        case kMP42VideoCodecType_SorensonVideo3:
            result = NSLocalizedString(@"Sorenson Video 3", nil);
            break;

        case kMP42VideoCodecType_Theora:
            result = NSLocalizedString(@"Theora", nil);
            break;

        case kMP42VideoCodecType_VP8:
            result = NSLocalizedString(@"VP8", nil);
            break;

        case kMP42VideoCodecType_VP9:
            result = NSLocalizedString(@"VP9", nil);
            break;

        case kMP42VideoCodecType_AV1:
            result = NSLocalizedString(@"AV1", nil);
            break;

        case kMP42VideoCodecType_AppleProRes4444:
            result = NSLocalizedString(@"ProRes 4444", nil);
            break;

        case kMP42VideoCodecType_AppleProRes422HQ:
            result = NSLocalizedString(@"ProRes 422 HQ", nil);
            break;

        case kMP42VideoCodecType_AppleProRes422:
            result = NSLocalizedString(@"ProRes 422", nil);
            break;

        case kMP42VideoCodecType_AppleProRes422LT:
            result = NSLocalizedString(@"ProRes 422 LT", nil);
            break;

        case kMP42VideoCodecType_AppleProRes422Proxy:
            result = NSLocalizedString(@"ProRes 422 Proxy", nil);
            break;

        case kMP42VideoCodecType_AppleProResRAW:
            result = NSLocalizedString(@"ProRes RAW", nil);
            break;
        case kMP42VideoCodecType_DVCNTSC:
            result = NSLocalizedString(@"DV NTSC", nil);
            break;

        case kMP42VideoCodecType_DVCPAL:
            result = NSLocalizedString(@"DV PAL", nil);
            break;

        case kMP42VideoCodecType_DVCProPAL:
            result = NSLocalizedString(@"DVC Pro PAL", nil);
            break;

        case kMP42VideoCodecType_XAVC_Long_GOP:
            result = NSLocalizedString(@"XAVC Long GOP", nil);
            break;

        case kMP42VideoCodecType_FairPlay:
            result = NSLocalizedString(@"FairPlay Video", nil);
            break;

        default:
            break;
    }

    return result;
}

NSString *localizedAudioDisplayName(FourCharCode mediaSubtype)
{
    NSString *result = @(FourCC2Str(mediaSubtype));

    switch (mediaSubtype) {
        case kMP42AudioCodecType_MPEG4AAC:
            result = NSLocalizedString(@"AAC", nil);
            break;

        case kMP42AudioCodecType_MPEG4AAC_HE:
            result = NSLocalizedString(@"HE-AAC", nil);
            break;

        case kMP42AudioCodecType_MPEGLayer1:
            result = NSLocalizedString(@"MP1", nil);
            break;

        case kMP42AudioCodecType_MPEGLayer2:
            result = NSLocalizedString(@"MP2", nil);
            break;

        case kMP42AudioCodecType_MPEGLayer3:
            result = NSLocalizedString(@"MP3", nil);
            break;

        case kMP42AudioCodecType_Vorbis:
            result = NSLocalizedString(@"Vorbis", nil);
            break;

        case kMP42AudioCodecType_FLAC:
            result = NSLocalizedString(@"FLAC", nil);
            break;

        case kMP42AudioCodecType_AppleLossless:
            result = NSLocalizedString(@"Apple Lossless", nil);
            break;

        case kMP42AudioCodecType_AC3:
            result = NSLocalizedString(@"AC3", nil);
            break;

        case kMP42AudioCodecType_EnhancedAC3:
            result = NSLocalizedString(@"E-AC3", nil);
            break;

        case kMP42AudioCodecType_DTS:
            result = NSLocalizedString(@"DTS", nil);
            break;

        case kMP42AudioCodecType_TrueHD:
            result = NSLocalizedString(@"True HD", nil);
            break;

        case kMP42AudioCodecType_Opus:
            result = NSLocalizedString(@"Opus", nil);
            break;

        case kMP42AudioCodecType_TTA:
            result = NSLocalizedString(@"True Audio", nil);
            break;

        case kMP42AudioCodecType_FairPlay:
            result = NSLocalizedString(@"FairPlay Sound", nil);
            break;

        case kMP42AudioCodecType_FairPlay_AAC:
            result = NSLocalizedString(@"FairPlay AAC", nil);
            break;

        case kMP42AudioCodecType_FairPlay_AC3:
            result = NSLocalizedString(@"FairPlay AC3", nil);
            break;

        case kMP42AudioCodecType_LinearPCM:
            result = NSLocalizedString(@"PCM", nil);
            break;

        case kMP42AudioEmbeddedExtension_JOC:
            result = NSLocalizedString(@"Atmos", nil);
            break;

        default:
            break;
    }
    
    return result;
}

NSString *localizedSubtitlesDisplayName(FourCharCode mediaSubtype)
{
    NSString *result = @(FourCC2Str(mediaSubtype));

    switch (mediaSubtype) {
        case kMP42SubtitleCodecType_Text:
            result = NSLocalizedString(@"Text", nil);
            break;

        case kMP42SubtitleCodecType_3GText:
            result = NSLocalizedString(@"Tx3g", nil);
            break;

        case kMP42SubtitleCodecType_WebVTT:
            result = NSLocalizedString(@"WebVTT", nil);
            break;

        case kMP42SubtitleCodecType_VobSub:
            result = NSLocalizedString(@"VobSub", nil);
            break;

        case kMP42SubtitleCodecType_PGS:
            result = NSLocalizedString(@"PGS", nil);
            break;

        case kMP42SubtitleCodecType_SSA:
            result = NSLocalizedString(@"SSA", nil);
            break;

        case kMP42SubtitleCodecType_FairPlay:
            result = NSLocalizedString(@"FairPlay Tx3g", nil);
            break;

        default:
            break;
    }
    
    return result;
}

NSString *localizedClosedCaptionDisplayName(FourCharCode mediaSubtype)
{
    NSString *result = @(FourCC2Str(mediaSubtype));

    switch (mediaSubtype) {
        case kMP42ClosedCaptionCodecType_CEA608:
            result = NSLocalizedString(@"CEA-608", nil);
            break;

        case kMP42ClosedCaptionCodecType_CEA708:
            result = NSLocalizedString(@"CEA-708", nil);
            break;

        case kMP42ClosedCaptionCodecType_ATSC:
            result = NSLocalizedString(@"ATSC", nil);
            break;

        case kMP42ClosedCaptionCodecType_FairPlay:
            result = NSLocalizedString(@"FairPlay CEA-608", nil);
            break;

        default:
            break;
    }
    
    return result;
}

NSString *localizedTimeCodeDisplayName(FourCharCode mediaSubtype)
{
    NSString *result = @(FourCC2Str(mediaSubtype));

    switch (mediaSubtype) {
        case kMP42TimeCodeFormatType_TimeCode32:
            result = NSLocalizedString(@"TimeCode", nil);
            break;

        case kMP42TimeCodeFormatType_TimeCode64:
            result = NSLocalizedString(@"TimeCode 64", nil);
            break;

        case kMP42TimeCodeFormatType_Counter32:
            result = NSLocalizedString(@"Counter 32", nil);
            break;

        case kMP42TimeCodeFormatType_Counter64:
            result = NSLocalizedString(@"Counter 64", nil);
            break;

        default:
            break;
    }
    
    return result;
}

NSString *localizedMetadataDisplayName(FourCharCode mediaSubtype)
{
    NSString *result = @(FourCC2Str(mediaSubtype));

    switch (mediaSubtype) {
        case kMP42MetadataFormatType_TimedMetadata:
            result = NSLocalizedString(@"Timed Metadata", nil);
            break;

        default:
            break;
    }

    return result;
}

NSString *localizedDisplayName(FourCharCode mediaType, FourCharCode mediaSubtype)
{
    NSString *result = @(FourCC2Str(mediaSubtype));

    switch (mediaType) {
        case kMP42MediaType_Video:
            result = localizedVideoDisplayName(mediaSubtype);
            break;
        case kMP42MediaType_Audio:
            result = localizedAudioDisplayName(mediaSubtype);
            break;
        case kMP42MediaType_Text:
        case kMP42MediaType_Subtitle:
        case kMP42MediaType_Subpic:
            result = localizedSubtitlesDisplayName(mediaSubtype);
            break;
        case kMP42MediaType_ClosedCaption:
            result = localizedClosedCaptionDisplayName(mediaSubtype);
            break;
        case kMP42MediaType_TimeCode:
            result = localizedTimeCodeDisplayName(mediaSubtype);
            break;
        case kMP42MediaType_OD:
            result = NSLocalizedString(@"MPEG-4 ODSM", nil);
            break;
        case kMP42MediaType_Scene:
            result = NSLocalizedString(@"MPEG-4 SDSM", nil);
            break;
        case kMP42MediaType_Control:
            result = NSLocalizedString(@"MPEG-4 Control", nil);
            break;
        case kMP42MediaType_Hint:
            result = NSLocalizedString(@"Hint", nil);
            break;
        case kMP42MediaType_Metadata:
            result = localizedMetadataDisplayName(mediaSubtype);
            break;

        default:
            break;
    }

    return result;
}
