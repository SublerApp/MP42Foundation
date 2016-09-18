/*
 *  MP42Utilities.h
 *  Subler
 *
 *  Created by Damiano Galassi on 30/01/09.
 *  Copyright 2009 Damiano Galassi. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>
#import "MP42Utilities.h"
#include "mp4v2.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {  TRACK_DISABLED = 0x0,
    TRACK_ENABLED = 0x1,
    TRACK_IN_MOVIE = 0x2,
    TRACK_IN_PREVIEW = 0x4,
    TRACK_IN_POSTER = 0x8
} track_header_flags;

NSString* SRTStringFromTime( long long time, long timeScale , const char separator);

int MP4SetTrackEnabled(MP4FileHandle fileHandle, MP4TrackId trackId);
int MP4SetTrackDisabled(MP4FileHandle fileHandle, MP4TrackId trackId);

int updateTracksCount(MP4FileHandle fileHandle);
void updateMoovDuration(MP4FileHandle fileHandle);

uint64_t getTrackSize(MP4FileHandle fileHandle, MP4TrackId trackId);

MP4TrackId findChapterTrackId(MP4FileHandle fileHandle);
MP4TrackId findChapterPreviewTrackId(MP4FileHandle fileHandle);

void removeAllChapterTrackReferences(MP4FileHandle fileHandle);
MP4TrackId findFirstVideoTrack(MP4FileHandle fileHandle);

uint16_t getFixedVideoWidth(MP4FileHandle fileHandle, MP4TrackId videoTrack);

NSString* getTrackName(MP4FileHandle fileHandle, MP4TrackId videoTrack);
FourCharCode getTrackMediaType(MP4FileHandle fileHandle, MP4TrackId Id);
FourCharCode getTrackMediaSubType(MP4FileHandle fileHandle, MP4TrackId Id);
NSString* getHumanReadableTrackLanguage(MP4FileHandle fileHandle, MP4TrackId videoTrack);
NSString* getFilenameLanguage(CFStringRef filename);

uint8_t *CreateEsdsFromSetupData(uint8_t *codecPrivate, size_t vosLen, size_t *esdsLen, int trackID, bool audio, bool write_version);
ComponentResult ReadESDSDescExt(void* descExt, UInt8 **buffer, int *size, int versionFlags);

int64_t getTrackStartOffset(MP4FileHandle fileHandle, MP4TrackId Id);
void setTrackStartOffset(MP4FileHandle fileHandle, MP4TrackId Id, int64_t offset);
int copyTrackEditLists (MP4FileHandle fileHandle, MP4TrackId srcTrackId, MP4TrackId dstTrackId);

NSError* MP42Error(NSString *description, NSString* recoverySuggestion, NSInteger code);
int yuv2rgb(int yuv);
int rgb2yuv(int rgb);

void *fast_realloc_with_padding(void *ptr, unsigned int *size, unsigned int min_size);
int DecompressZlib(uint8_t **sampleData, uint32_t *sampleSize);
int DecompressBzlib(uint8_t **sampleData, uint32_t *sampleSize);

#ifdef __cplusplus
}
#endif
