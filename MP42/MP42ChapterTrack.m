//
//  MP42ChapterTrack.m
//  Subler
//
//  Created by Damiano Galassi on 06/02/09.
//  Copyright 2009 Damiano Galassi. All rights reserved.
//

#import "MP42ChapterTrack.h"
#import "MP42SubUtilities.h"
#import "MP42PrivateUtilities.h"
#import "MP42MediaFormat.h"

@implementation MP42ChapterTrack

- (instancetype)init
{
    if ((self = [super init])) {
        _name = [self defaultName];
        _format = MP42SubtitleFormatText;
        _language = @"English";
        _isEdited = NO;
        _muxed = NO;
        _enabled = NO;
        _mediaType = MP42MediaTypeText;

        chapters = [[NSMutableArray alloc] init];
    }

    return self;
}

- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP4FileHandle)fileHandle
{
    if ((self = [super initWithSourceURL:URL trackID:trackID fileHandle:fileHandle])) {
        if (!_name || [_name isEqualToString:@"Text Track"])
            _name = [self defaultName];
        if (!_format)
            _format = MP42SubtitleFormatText;

        _mediaType = MP42MediaTypeText;
        chapters = [[NSMutableArray alloc] init];

        MP4Chapter_t *chapter_list = NULL;
        uint32_t      chapter_count;

        MP4GetChapters(fileHandle, &chapter_list, &chapter_count, MP4ChapterTypeQt);

        unsigned int i = 1;
        MP4Duration sum = 0;
        while (i <= chapter_count) {
            MP42TextSample *chapter = [[MP42TextSample alloc] init];

            char *title = chapter_list[i-1].title;
            if ((title[0] == '\xfe' && title[1] == '\xff') || (title[0] == '\xff' && title[1] == '\xfe')) {
                chapter.title = [[[NSString alloc] initWithBytes:title
														  length:chapter_list[i-1].titleLength
														encoding:NSUTF16StringEncoding] autorelease];
            } else {
                chapter.title = [NSString stringWithCString:chapter_list[i-1].title encoding: NSUTF8StringEncoding];
            }

            chapter.timestamp = sum;
            sum = chapter_list[i-1].duration + sum;
            [chapters addObject:chapter];
            [chapter release];
            i++;
        }
        MP4Free(chapter_list);
    }

    return self;
}

- (instancetype)initWithTextFile:(NSURL *)URL
{
    if ((self = [super init])) {
        _name = [self defaultName];
        _format = MP42SubtitleFormatText;
        _sourceURL = [URL retain];
        _language = @"English";
        _isEdited = YES;
        _muxed = NO;
        _enabled = NO;
        _mediaType = MP42MediaTypeText;
        _areChaptersEdited = YES;

        chapters = [[NSMutableArray alloc] init];
        LoadChaptersFromPath([_sourceURL path], chapters);
        [chapters sortUsingSelector:@selector(compare:)];
    }
    
    return self;
}

+ (instancetype)chapterTrackFromFile:(NSURL *)URL
{
    return [[[MP42ChapterTrack alloc] initWithTextFile:URL] autorelease];
}

- (NSUInteger)addChapter:(MP42TextSample *)chapter
{
    self.isEdited = YES;
    _areChaptersEdited = YES;

    [chapters addObject:chapter];
    [chapters sortUsingSelector:@selector(compare:)];

    return [chapters indexOfObject:chapter];
}

- (NSUInteger)addChapter:(NSString *)title duration:(uint64_t)timestamp
{
    MP42TextSample *newChapter = [[MP42TextSample alloc] init];
    newChapter.title = title;
    newChapter.timestamp = timestamp;

    NSUInteger idx = [self addChapter:newChapter];
    [newChapter release];

    return idx;
}

- (NSUInteger)addChapter:(NSString *)title image:(MP42Image *)image duration:(uint64_t)timestamp {
    MP42TextSample *newChapter = [[MP42TextSample alloc] init];
    newChapter.title = title;
    newChapter.image = image;
    newChapter.timestamp = timestamp;

    NSUInteger idx = [self addChapter:newChapter];
    [newChapter release];

    return idx;
}

- (NSUInteger)indexOfChapter:(MP42TextSample *)chapterSample {
    return [chapters indexOfObject:chapterSample];
}

- (void)removeChapterAtIndex:(NSUInteger)index
{
    [self removeChaptersAtIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (void)removeChaptersAtIndexes:(NSIndexSet *)indexes
{
    self.isEdited = YES;
    _areChaptersEdited = YES;
    [chapters removeObjectsAtIndexes:indexes];
}

- (void)setTimestamp:(MP4Duration)timestamp forChapter:(MP42TextSample *)chapterSample
{
    self.isEdited = YES;
    _areChaptersEdited = YES;
    [chapterSample setTimestamp:timestamp];
    [chapters sortUsingSelector:@selector(compare:)];
}

- (void)setTitle:(NSString *)title forChapter:(MP42TextSample *)chapterSample
{
    self.isEdited = YES;
    _areChaptersEdited = YES;
    [chapterSample setTitle:title];
}

- (MP42TextSample *)chapterAtIndex:(NSUInteger)index
{
    return [chapters objectAtIndex:index];
}

- (BOOL)writeToFile:(MP4FileHandle)fileHandle error:(NSError **)outError
{
    BOOL success = YES;

    if ((_isEdited && _areChaptersEdited) || !_muxed) {
        MP4Chapter_t * fileChapters = 0;
        MP4Duration refTrackDuration;
        uint32_t chapterCount = 0;
        uint32_t i = 0;
        uint64_t sum = 0, moovDuration;

        // get the list of chapters
        MP4GetChapters(fileHandle, &fileChapters, &chapterCount, MP4ChapterTypeQt);

        MP4DeleteChapters(fileHandle, MP4ChapterTypeAny, _Id);
        updateTracksCount(fileHandle);

        MP4TrackId refTrack = findFirstVideoTrack(fileHandle);
        if (!refTrack)
            refTrack = 1;

        chapterCount = [chapters count];
        
        if (chapterCount) {
            // Insert a chapter at time 0 if there isn't one
            MP42TextSample * chapter = [chapters objectAtIndex:0];
            if (chapter.timestamp != 0) {
                MP42TextSample *st = [[MP42TextSample alloc] init];
                st.timestamp = 0;
                st.title = @"Chapter 0";
                [chapters insertObject:st atIndex:0];
                [st release];
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
                MP42TextSample * chapter = [chapters objectAtIndex:i];
                if ([[chapter title] UTF8String])
                    strcpy(fileChapters[i].title, [[chapter title] UTF8String]);

                if (i + 1 < chapterCount && sum < refTrackDuration) {
                    MP42TextSample * nextChapter = [chapters objectAtIndex:i+1];
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
            MP4SetChapters(fileHandle, fileChapters, i, MP4ChapterTypeAny);

            free(fileChapters);
            success = _Id = findChapterTrackId(fileHandle);
        }
    }

    if (!success) {
        if (outError != NULL)
            *outError = MP42Error(@"Failed to mux chapters into mp4 file",
                                  nil,
                                  120);

        return success;
    } else if (_Id) {
        success = [super writeToFile:fileHandle error:outError];
    }

    return success;
}

- (NSInteger)chapterCount
{
  return [chapters count];
}

- (BOOL)exportToURL:(NSURL *)url error:(NSError **)error
{
	NSMutableString* file = [[[NSMutableString alloc] init] autorelease];
	NSUInteger x = 0;

	for (MP42TextSample * chapter in chapters) {
		[file appendFormat:@"CHAPTER%02lu=%@\nCHAPTER%02luNAME=%@\n", (unsigned long)x, SRTStringFromTime([chapter timestamp], 1000, '.'), (unsigned long)x, [chapter title]];
		x++;
	}

	return [file writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (NSString *)defaultName {
    return @"Chapter Track";
}

- (BOOL)updateFromCSVFile:(NSURL *)URL error:(NSError **)outError {
    NSArray *csvData = [NSArray arrayWithContentsOfCSVURL:URL];
    if (csvData.count == self.chapterCount) {
        for (NSInteger i = 0; i < csvData.count; ++i) {
            NSArray *lineFields = csvData[i];
            if (lineFields.count != 2 || [lineFields[0] integerValue] != i + 1) {
                if (NULL != outError)
                    *outError = MP42Error(@"Invalid chapters CSV file.", @"The CSV file is not a valid chapters CSV file.", 150);
                return NO;
            }
        }
        for (NSInteger i = 0; i < csvData.count; ++i) {
            MP42TextSample *chapter = self.chapters[i];
            chapter.title = csvData[i][1];
        }
        return YES;
    }
    if (NULL != outError)
        *outError = MP42Error(@"Incorrect line count", @"The line count in the chapters CSV file does not match the number of chapters in the movie.", 151);
    return NO;
}

@synthesize chapters;

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    [coder encodeObject:chapters forKey:@"chapters"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];

    chapters = [[decoder decodeObjectForKey:@"chapters"] retain];

    return self;
}

- (void)dealloc
{
    [chapters release];
    [super dealloc];
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
+ (NSArray<NSArray<NSString *> *> * __nullable)arrayWithContentsOfCSVURL:(NSURL *)url;
{
    NSString *str1 = STLoadFileWithUnknownEncoding(url.path);
    NSMutableString *csvString = STStandardizeStringNewlines(str1);
    if (!csvString) return 0;
    
    if ([csvString characterAtIndex:0] == 0xFEFF) [csvString deleteCharactersInRange:NSMakeRange(0,1)];
    if ([csvString characterAtIndex:[csvString length]-1] != '\n') [csvString appendFormat:@"%c",'\n'];
    NSScanner *sc = [NSScanner scannerWithString:csvString];
    sc.charactersToBeSkipped =  nil;
    NSMutableArray *csvArray = [NSMutableArray array];
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
