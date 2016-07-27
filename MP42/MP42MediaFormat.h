//
//  MP42MediaFormat.h
//  Subler
//
//  Created by Damiano Galassi on 08/08/13.
//
//

#import <Foundation/Foundation.h>

/* MP4 primitive types */
typedef void*       MP42FileHandle;
typedef uint32_t    MP42TrackId;
typedef uint64_t    MP42Duration;

// File Type
extern NSString *const MP42FileTypeMP4;
extern NSString *const MP42FileTypeM4V;
extern NSString *const MP42FileTypeM4A;
extern NSString *const MP42FileTypeM4B;
extern NSString *const MP42FileTypeM4R;

// Media Type
extern NSString *const MP42MediaTypeVideo;
extern NSString *const MP42MediaTypeAudio;
extern NSString *const MP42MediaTypeText;
extern NSString *const MP42MediaTypeClosedCaption;
extern NSString *const MP42MediaTypeSubtitle;
extern NSString *const MP42MediaTypeTimecode;
extern NSString *const MP42MediaTypeMetadata;
extern NSString *const MP42MediaTypeMuxed;


// Video Format
extern NSString *const MP42VideoFormatH265;
extern NSString *const MP42VideoFormatH264;
extern NSString *const MP42VideoFormatMPEG4Visual;
extern NSString *const MP42VideoFormatSorenson;
extern NSString *const MP42VideoFormatSorenson3;
extern NSString *const MP42VideoFormatMPEG1;
extern NSString *const MP42VideoFormatMPEG2;
extern NSString *const MP42VideoFormatDV;
extern NSString *const MP42VideoFormatPNG;
extern NSString *const MP42VideoFormatAnimation;
extern NSString *const MP42VideoFormatProRes;
extern NSString *const MP42VideoFormatJPEG;
extern NSString *const MP42VideoFormatMotionJPEG;
extern NSString *const MP42VideoFormatFairPlay;


// Audio Format
extern NSString *const MP42AudioFormatAAC;
extern NSString *const MP42AudioFormatHEAAC;
extern NSString *const MP42AudioFormatMP1;
extern NSString *const MP42AudioFormatMP2;
extern NSString *const MP42AudioFormatMP3;
extern NSString *const MP42AudioFormatVorbis;
extern NSString *const MP42AudioFormatFLAC;
extern NSString *const MP42AudioFormatALAC;
extern NSString *const MP42AudioFormatAC3;
extern NSString *const MP42AudioFormatEAC3;
extern NSString *const MP42AudioFormatDTS;
extern NSString *const MP42AudioFormatTrueHD;
extern NSString *const MP42AudioFormatOpus;
extern NSString *const MP42AudioFormatAMR;
extern NSString *const MP42AudioFormatPCM;
extern NSString *const MP42AudioFormatFairPlay;


// Subtitle Format
extern NSString *const MP42SubtitleFormatWebVTT;
extern NSString *const MP42SubtitleFormatTx3g;
extern NSString *const MP42SubtitleFormatText;
extern NSString *const MP42SubtitleFormatVobSub;
extern NSString *const MP42SubtitleFormatPGS;
extern NSString *const MP42SubtitleFormatSSA;
extern NSString *const MP42SubtitleFormatFairPlay;


// Closed Caption Fromat
extern NSString *const MP42ClosedCaptionFormatCEA608;
extern NSString *const MP42ClosedCaptionFormatCEA708;
extern NSString *const MP42ClosedCaptionFormatFairPlay;


// TimeCode Format
extern NSString *const MP42TimeCodeFormat;

// Audio downmixes
extern NSString * const SBMonoMixdown;
extern NSString * const SBStereoMixdown;
extern NSString * const SBDolbyMixdown;
extern NSString * const SBDolbyPlIIMixdown;
