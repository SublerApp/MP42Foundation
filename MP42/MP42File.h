//
//  MP42File.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MP42Track.h"
#import "MP42VideoTrack.h"
#import "MP42AudioTrack.h"
#import "MP42SubtitleTrack.h"
#import "MP42ClosedCaptionTrack.h"
#import "MP42ChapterTrack.h"
#import "MP42Metadata.h"

#import "MP42MediaFormat.h"
#import "MP42Logging.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MP4264BitData;
extern NSString * const MP4264BitTime;
extern NSString * const MP42GenerateChaptersPreviewTrack;
extern NSString * const MP42CustomChaptersPreviewTrack;
extern NSString * const MP42OrganizeAlternateGroups;

/**
 *  MP42Status
 */
typedef NS_ENUM(NSUInteger, MP42Status) {
    MP42StatusLoaded = 0,
    MP42StatusReading,
    MP42StatusWriting
};

/**
 *  MP42FileDelegate
 */
@protocol MP42FileDelegate <NSObject>
@optional
- (void)progressStatus:(CGFloat)progress;
@end

@class MP42Muxer;
@class MP42FileImporter;

/**
 *  A MP42File object is an object that represents a mp4 file.
 */
@interface MP42File : NSObject <NSCoding> {
@private
    MP42FileHandle   _fileHandle;
    NSURL           *_fileURL;

    id <MP42FileDelegate> _delegate;

    MP42Status  _status;
    BOOL        _cancelled;

    NSMutableArray<__kindof MP42Track *>  *_tracks;
    NSMutableArray<MP42Track *>  *_tracksToBeDeleted;
    MP42Metadata    *_metadata;
    MP42Muxer       *_muxer;
    NSMutableDictionary<NSString *, MP42FileImporter *> *_importers;

    BOOL        _hasFileRepresentation;

}

+ (void)setGlobalLogger:(id <MP42Logging>)logger;

@property(nonatomic, readwrite, assign) id <MP42FileDelegate> delegate;

/**
 * indicates the URL with which the instance of MP42File was initialized.
 */
@property(nonatomic, readonly, nullable) NSURL *URL;

/**
 * Provides access to the mp4 file MP42Metadata instance.
 */
@property(nonatomic, readonly) MP42Metadata *metadata;

/**
 * Indicates whether a MP4File has a representation on disk.
 */
@property(nonatomic, readonly) BOOL hasFileRepresentation;

/**
 * Indicates the duration of the file.
 */
@property(nonatomic, readonly) NSUInteger duration;

/**
 * Indicates the size of the file. It can be approximated.
 */
@property(nonatomic, readonly) uint64_t dataSize;

/**
 *  Creates a MP42File instance.
 *
 *  @param del the object delegate
 *
 *  @return An instance of MP42File
 */

- (instancetype)initWithDelegate:(id <MP42FileDelegate>)del;

/**
 *  Creates a MP42File instance from the passed URL.
 *
 *  @param URL an instance of NSURL that references a mp4 file.
 *  @param del the object delegate
 *
 *  @return An instance of MP42File
 */
- (instancetype)initWithExistingFile:(NSURL *)URL andDelegate:(nullable id <MP42FileDelegate>)del;

/**
 * Provides the array of MP42Tracks contained by the mp4 file
 */
@property(nonatomic, readonly, copy) NSArray<MP42Track *> *tracks;

/**
 *  Provides an instance of MP42Track that represents the track of the specified index.
 *
 *  @param index The index of the requested MP42Track in the tracks array
 *
 *  @return An instance of MP42Track; may raise an exception if out of bounds.
 */
- (MP42Track *)trackAtIndex:(NSUInteger)index;

/**
 *  Provides an instance of MP42Track that represents the track of the specified trackID.
 *
 *  @param trackID The trackID of the requested MP42Track
 *
 *  @return An instance of MP42Track; may be nil if no track of the specified trackID is available.
 */
- (nullable MP42Track *)trackWithTrackID:(NSUInteger)trackID;

/**
 *  Provides an array of MP42Track of the file that present media of the specified media type.
 *
 *  @param mediaType a media type defined in MP42MediaFormat.h
 *
 *  @return An NSArray of MP42Tracks; may be empty if no tracks of the specified media type are available.
 */
- (NSArray<MP42Track *> *)tracksWithMediaType:(NSString *)mediaType;

/**
 *  Add a track to the mp4 file.
 *
 *  @param track A MP42Track instance.
 *
 */
- (void)addTrack:(MP42Track *)track;

/**
 *  Removes a track at the index.
 *
 *  @param index The track index.
 */
- (void)removeTrackAtIndex:(NSUInteger)index;

/**
 *  Removes the tracks at the passed indexes.
 *
 *  @param indexes A NSIndexSet of indexes.
 */
- (void)removeTracksAtIndexes:(NSIndexSet *)indexes;

- (void)moveTrackAtIndex:(NSUInteger)index toIndex:(NSUInteger)newIndex;

/**
 *  Provides an instance of MP42ChapterTrack that represents the file chapters.
 *
 *  @return An instance of MP42ChapterTrack.  may be nil if no chapter track is available.
 */
- (MP42ChapterTrack *)chapters;

/** 
 * Creates a set of alternate group the way iTunes and Apple devices want:
 * one alternate group for sound, one for subtitles, a disabled photo-jpeg track,
 * a disabled chapter track, and a video track with no alternate group
 */
- (void)organizeAlternateGroups;

/**
 *  Reads an existing mp4 file and writes a new version of the file with the two important changes:
 *
 * First, the mp4 control information is moved to the beginning of the file. (Frequenty it is at the end of the file due to it being constantly modified as track samples are added to an mp4 file.) This optimization is useful in that in allows the mp4 file to be HTTP streamed.
 *
 * Second, the track samples are interleaved so that the samples for a particular instant in time are colocated within the file. This eliminates disk seeks during playback of the file which results in better performance.
 *
 * There are also two important side effects of optimize:
 *
 * First, any free blocks within the mp4 file are eliminated.
 *
 * Second, as a side effect of the sample interleaving process any media data chunks that are not actually referenced by the mp4 control structures are deleted. This is useful if you have called removeTrack: which only deletes the control information for a track, and not the actual media data.
 *
 *  @return returns the operation result
 */
- (BOOL)optimize;

/**
 *  Exports a MP42File object.
 *
 *  @param url        An NSURL object that specifies a url to a file.
 *  @param attributes An NSDictionary object that specifies the desired operation and its options,
 *  @param outError   A pointer to an NSError object; if the operation fails, an NSError object is returned in this location.
 *
 *  @return YES if the movie file was successfully created, NO otherwise.
 */
- (BOOL)writeToUrl:(NSURL *)url withAttributes:(NSDictionary *)attributes error:(NSError **)outError;

/**
 *  Updates a MP42File object.
 *
 *  @param attributes An NSDictionary object that specifies the desired operation and its options.
 *  @param outError   A pointer to an NSError object; if the operation fails, an NSError object is returned in this location.
 *
 *  @return YES if the movie file was successfully created, NO otherwise.
 */
- (BOOL)updateMP4FileWithAttributes:(NSDictionary *)attributes error:(NSError **)outError;

/**
 *  Cancels a write/update operation.
 */
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
