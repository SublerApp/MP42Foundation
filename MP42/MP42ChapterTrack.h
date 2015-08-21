//
//  MP42ChapterTrack.h
//  Subler
//
//  Created by Damiano Galassi on 06/02/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42Track.h"
#import "MP42TextSample.h"

NS_ASSUME_NONNULL_BEGIN

@interface MP42ChapterTrack : MP42Track <NSCoding> {
@private
    NSMutableArray<MP42TextSample *> *chapters;
    BOOL _areChaptersEdited;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle;
+ (instancetype)chapterTrackFromFile:(NSURL *)URL;

- (NSUInteger)addChapter:(MP42TextSample *)chapter;
- (NSUInteger)addChapter:(NSString *)title duration:(uint64_t)timestamp;
- (NSUInteger)addChapter:(NSString *)title image:(MP42Image *)image duration:(uint64_t)timestamp;

- (void)removeChapterAtIndex:(NSUInteger)index;
- (void)removeChaptersAtIndexes:(NSIndexSet *)indexes;

- (NSUInteger)indexOfChapter:(MP42TextSample *)chapterSample;

- (void)setTimestamp:(MP42Duration)timestamp forChapter:(MP42TextSample *)chapterSample;
- (void)setTitle:(NSString*)title forChapter:(MP42TextSample *)chapterSample;

- (MP42TextSample *)chapterAtIndex:(NSUInteger)index;

- (NSInteger)chapterCount;

- (BOOL)updateFromCSVFile:(NSURL *)URL error:(NSError **)outError;

- (BOOL)exportToURL:(NSURL *)url error:(NSError **)error;

@property(nonatomic, readonly, retain) NSArray *chapters;

@end

@interface NSArray (CSVAdditions)

+ (nullable NSArray<NSArray<NSString *> *> *)arrayWithContentsOfCSVURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
