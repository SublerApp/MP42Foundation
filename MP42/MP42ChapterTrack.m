//
//  MP42ChapterTrack.m
//  Subler
//
//  Created by Damiano Galassi on 06/02/09.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42ChapterTrack.h"
#import "MP42Track+Private.h"
#import "MP42SubUtilities.h"
#import "MP42PrivateUtilities.h"
#import "MP42MediaFormat.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42ChapterTrack {
@private
    NSMutableArray<MP42TextSample *> *_chapters;
    BOOL _areChaptersEdited;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.format = kMP42SubtitleCodecType_Text;
        self.mediaType = kMP42MediaType_Text;
        self.enabled = NO;
        self.muxed = NO;
        self.language = @"en";
        _chapters = [[NSMutableArray alloc] init];
    }

    return self;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(MP42TrackId)trackID fileHandle:(MP4FileHandle)fileHandle
{
    self = [super initWithSourceURL:URL trackID:trackID fileHandle:fileHandle];

    if (self) {

        if (!self.format) {
            self.format = kMP42SubtitleCodecType_Text;
        }

        _chapters = [[NSMutableArray alloc] init];

        MP4Chapter_t *chapter_list = NULL;
        uint32_t      chapter_count;

        MP4GetChapters(fileHandle, &chapter_list, &chapter_count, MP4ChapterTypeQt);

        unsigned int i = 1;
        MP4Duration sum = 0;
        while (i <= chapter_count) {
            MP42TextSample *chapter = [[MP42TextSample alloc] init];

            char *title = chapter_list[i-1].title;
            if ((title[0] == '\xfe' && title[1] == '\xff') || (title[0] == '\xff' && title[1] == '\xfe')) {
                chapter.title = [[NSString alloc] initWithBytes:title
                                                         length:chapter_list[i-1].titleLength
                                                       encoding:NSUTF16StringEncoding];
            } else {
                chapter.title = [NSString stringWithCString:chapter_list[i-1].title encoding: NSUTF8StringEncoding];
            }

            chapter.timestamp = sum;
            sum = chapter_list[i-1].duration + sum;
            [_chapters addObject:chapter];
            i++;
        }
        MP4Free(chapter_list);
    }

    return self;
}

- (instancetype)initWithTextFile:(NSURL *)URL
{
    self = [super init];
    if (self) {
        self.format = kMP42SubtitleCodecType_Text;
        self.mediaType = kMP42MediaType_Text;
        self.enabled = NO;
        self.language = @"en";
        self.URL = URL;
        self.edited = YES;
        self.muxed = NO;
        _areChaptersEdited = YES;

        _chapters = [[NSMutableArray alloc] init];
        LoadChaptersFromURL(self.URL, _chapters);
        [_chapters sortUsingSelector:@selector(compare:)];
    }
    
    return self;
}

+ (instancetype)chapterTrackFromFile:(NSURL *)URL
{
    return [[MP42ChapterTrack alloc] initWithTextFile:URL];
}

- (NSString *)defaultName {
    NSBundle *bundle = [NSBundle bundleForClass:[MP42ChapterTrack class]];
    return NSLocalizedStringFromTableInBundle(@"Chapter Track", @"Localizable", bundle, @"Default Chapter Track name");
}

- (NSUInteger)addChapter:(MP42TextSample *)chapter
{
    self.edited = YES;
    _areChaptersEdited = YES;

    [_chapters addObject:chapter];
    [_chapters sortUsingSelector:@selector(compare:)];

    return [_chapters indexOfObject:chapter];
}

- (NSUInteger)addChapter:(NSString *)title timestamp:(uint64_t)timestamp
{
    MP42TextSample *newChapter = [[MP42TextSample alloc] init];
    newChapter.title = title;
    newChapter.timestamp = timestamp;

    NSUInteger idx = [self addChapter:newChapter];

    return idx;
}

- (NSUInteger)addChapter:(NSString *)title image:(MP42Image *)image duration:(uint64_t)timestamp {
    MP42TextSample *newChapter = [[MP42TextSample alloc] init];
    newChapter.title = title;
    newChapter.image = image;
    newChapter.timestamp = timestamp;

    NSUInteger idx = [self addChapter:newChapter];

    return idx;
}

- (NSUInteger)indexOfChapter:(MP42TextSample *)chapterSample {
    return [_chapters indexOfObject:chapterSample];
}

- (void)removeChapterAtIndex:(NSUInteger)index
{
    [self removeChaptersAtIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (void)removeChaptersAtIndexes:(NSIndexSet *)indexes
{
    self.edited = YES;
    _areChaptersEdited = YES;
    [_chapters removeObjectsAtIndexes:indexes];
}

- (void)setTimestamp:(MP4Duration)timestamp forChapter:(MP42TextSample *)chapterSample
{
    self.edited = YES;
    _areChaptersEdited = YES;
    [chapterSample setTimestamp:timestamp];
    [_chapters sortUsingSelector:@selector(compare:)];
}

- (void)setTitle:(NSString *)title forChapter:(MP42TextSample *)chapterSample
{
    self.edited = YES;
    _areChaptersEdited = YES;
    [chapterSample setTitle:title];
}

- (MP42TextSample *)chapterAtIndex:(NSUInteger)index
{
    return [_chapters objectAtIndex:index];
}

- (BOOL)writeToFile:(MP4FileHandle)fileHandle error:(NSError * __autoreleasing *)outError
{
    BOOL success = YES;

    if ((self.edited && _areChaptersEdited) || !self.muxed) {
        MP4Chapter_t *fileChapters = 0;
        MP4Duration refTrackDuration;
        uint32_t chapterCount = 0;
        uint32_t i = 0;
        uint64_t sum = 0, moovDuration;

        MP4DeleteChapters(fileHandle, MP4ChapterTypeAny, self.trackId);
        updateTracksCount(fileHandle);

        MP4TrackId refTrack = findFirstVideoTrack(fileHandle);
        if (!refTrack) {
            refTrack = 1; 
        }

        chapterCount = (uint32_t)_chapters.count;
        
        if (chapterCount) {
            // Insert a chapter at time 0 if there isn't one
            MP42TextSample *firstChapter = _chapters.firstObject;

            if (firstChapter.timestamp != 0) {
                MP42TextSample *st = [[MP42TextSample alloc] init];
                st.timestamp = 0;
                st.title = @"Chapter 0";
                [_chapters insertObject:st atIndex:0];
                chapterCount++;
            }

            fileChapters = malloc(sizeof(MP4Chapter_t)*chapterCount);
            refTrackDuration = MP4ConvertFromTrackDuration(fileHandle,
                                                           refTrack,
                                                           MP4GetTrackDuration(fileHandle, refTrack),
                                                           MP4_MSECS_TIME_SCALE);
            MP4GetIntegerProperty(fileHandle, "moov.mvhd.duration", &moovDuration);
            moovDuration = (uint64_t) moovDuration * (double) 1000 / MP4GetTimeScale(fileHandle);
            if (refTrackDuration > moovDuration)
                refTrackDuration = moovDuration;

            for (i = 0; i < chapterCount; i++) {
                MP42TextSample *chapter = _chapters[i];
                const char *title = chapter.title.UTF8String;
                if (title) {
                    strlcpy(fileChapters[i].title, title, MP4V2_CHAPTER_TITLE_MAX + 1);
                }

                if (i + 1 < chapterCount && sum < refTrackDuration) {
                    MP42TextSample * nextChapter = [_chapters objectAtIndex:i+1];
                    fileChapters[i].duration = nextChapter.timestamp - chapter.timestamp;
                    sum = nextChapter.timestamp;
                } else {
                    fileChapters[i].duration = refTrackDuration - chapter.timestamp;
                }

                if (sum > refTrackDuration) {
                    fileChapters[i].duration = refTrackDuration - chapter.timestamp;
                    i++;
                    break;
                }
            }

            removeAllChapterTrackReferences(fileHandle);
            MP4SetChapters(fileHandle, fileChapters, i, MP4ChapterTypeQt);

            free(fileChapters);
            self.trackId = findChapterTrackId(fileHandle);
            success = self.trackId > 0;

            // Reset language
            self.language = self.language;
        }
    }

    if (!success) {
        if (outError != NULL)
            *outError = MP42Error(MP42LocalizedString(@"Failed to mux chapters into mp4 file", @"error message"),
                                  nil,
                                  120);

        return success;
    } else if (self.trackId) {
        success = [super writeToFile:fileHandle error:outError];
    }

    return success;
}

- (NSUInteger)chapterCount
{
  return _chapters.count;
}

- (BOOL)canExport
{
    return YES;
}

- (BOOL)exportToURL:(NSURL *)url error:(NSError * __autoreleasing *)error
{
	NSMutableString *file = [[NSMutableString alloc] init];
	NSUInteger x = 0;

	for (MP42TextSample *chapter in _chapters) {
		[file appendFormat:@"CHAPTER%02lu=%@\nCHAPTER%02luNAME=%@\n", (unsigned long)x, SRTStringFromTime([chapter timestamp], 1000, '.'), (unsigned long)x, [chapter title]];
		x++;
	}

	return [file writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (BOOL)updateFromCSVFile:(NSURL *)URL error:(NSError * __autoreleasing *)outError {
    NSArray<NSArray<NSString *> *> *csvData = [NSArray arrayWithContentsOfCSVURL:URL];
    if (csvData.count == self.chapterCount) {
        for (NSUInteger i = 0; i < csvData.count; ++i) {
            NSArray<NSString *> *lineFields = csvData[i];
            if (lineFields.count != 2 || lineFields[0].integerValue != i + 1) {
                if (NULL != outError)
                    *outError = MP42Error(MP42LocalizedString(@"Invalid chapters CSV file.", @"error message"),
                                          MP42LocalizedString(@"The CSV file is not a valid chapters CSV file.", @"error message"),
                                          150);
                return NO;
            }
        }
        for (NSUInteger i = 0; i < csvData.count; ++i) {
            MP42TextSample *chapter = self.chapters[i];
            chapter.title = csvData[i][1];
        }
        return YES;
    }
    if (NULL != outError)
        *outError = MP42Error(MP42LocalizedString(@"Incorrect line count", @"error message"),
                              MP42LocalizedString(@"The line count in the chapters CSV file does not match the number of chapters in the movie.", @"error message"),
                                                  151);
    return NO;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    [coder encodeObject:_chapters forKey:@"chapters"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    if (self) {
        _chapters = [decoder decodeObjectOfClasses:[NSSet setWithObjects:[NSMutableArray class], [MP42TextSample class], nil]
                                            forKey:@"chapters"];
    }

    return self;
}

@end

@implementation NSArray (CSVAdditions)

// CSV parsing examples
// CSV Record:
//     one,two,three
// Fields:
//     <one>
//     <two>
//     <three>
// CSV Record:
//     one, two, three
// Fields:
//     <one>
//     < two>
//     < three>
// CSV Record:
//     one,"2,345",three
// Fields:
//     <one>
//     <2,345>
//     <three>
// CSV record:
//     one,"John said, ""Hello there.""",three
// Explanation: inside a quoted field, two double quotes in a row count
// as an escaped double quote in the field data.
// Fields:
//     <one>
//     <John said, "Hello there.">
//     <three>
+ (nullable NSArray<NSArray<NSString *> *> *)arrayWithContentsOfCSVURL:(NSURL *)url
{
    NSString *str1 = STLoadFileWithUnknownEncoding(url);
    NSMutableString *csvString = STStandardizeStringNewlines(str1);
    if (!csvString) return 0;
    
    if ([csvString characterAtIndex:0] == 0xFEFF) [csvString deleteCharactersInRange:NSMakeRange(0,1)];
    if ([csvString characterAtIndex:[csvString length]-1] != '\n') [csvString appendFormat:@"%c",'\n'];
    NSScanner *sc = [NSScanner scannerWithString:csvString];
    sc.charactersToBeSkipped =  nil;
    NSMutableArray<NSMutableArray<NSString *> *> *csvArray = [NSMutableArray array];
    [csvArray addObject:[NSMutableArray array]];
    NSCharacterSet *commaNewlineCS = [NSCharacterSet characterSetWithCharactersInString:@",\n"];
    while (sc.scanLocation < csvString.length) {
        if ([sc scanString:@"\"" intoString:NULL]) {
            // Quoted field
            NSMutableString *field = [NSMutableString string];
            BOOL done = NO;
            NSString *quotedString;
            // Scan until we get to the end double quote or the EOF.
            while (!done && sc.scanLocation < csvString.length) {
                if ([sc scanUpToString:@"\"" intoString:&quotedString])
                    [field appendString:quotedString];
                if ([sc scanString:@"\"\"" intoString:NULL]) {
                    // Escaped double quote inside the quoted string.
                    [field appendString:@"\""];
                }
                else {
                    done = YES;
                }
            }
            if (sc.scanLocation < csvString.length) {
                ++sc.scanLocation;
                BOOL nextIsNewline = [sc scanString:@"\n" intoString:NULL];
                BOOL nextIsComma = NO;
                if (!nextIsNewline)
                    nextIsComma = [sc scanString:@"," intoString:NULL];
                if (nextIsNewline || nextIsComma) {
                    [[csvArray lastObject] addObject:field];
                    if (nextIsNewline && sc.scanLocation < csvString.length) {
                        [csvArray addObject:[NSMutableArray array]];
                    }
                }
                else {
                    // Quoted fields must be immediately followed by a comma or newline.
                    return nil;
                }
            }
            else {
                // No close quote found before EOF, so file is invalid CSV.
                return nil;
            }
        }
        else {
            NSString *field;
            [sc scanUpToCharactersFromSet:commaNewlineCS intoString:&field];
            BOOL nextIsNewline = [sc scanString:@"\n" intoString:NULL];
            BOOL nextIsComma = NO;
            if (!nextIsNewline)
                nextIsComma = [sc scanString:@"," intoString:NULL];
            if (nextIsNewline || nextIsComma) {
                [[csvArray lastObject] addObject:field];
                if (nextIsNewline && sc.scanLocation < csvString.length) {
                    [csvArray addObject:[NSMutableArray array]];
                }
            }
        }
    }
    return csvArray;
}

@end
