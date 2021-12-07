//
//  SubUtilities.m
//  Subler
//
//  Created by Alexander Strange on 7/24/07.
//  Copyright 2007 Perian. All rights reserved.
//

#import "MP42SubUtilities.h"
#import "MP42SampleBuffer.h"
#import "MP42HtmlParser.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42SubSerializer
{
    // input lines, sorted by 1. beginning time 2. original insertion order
    NSMutableArray<MP42SubLine *> *lines;

    uint64_t last_begin_time, last_end_time;
    uint64_t linesInput;
}

- (instancetype)init
{
	if ((self = [super init])) {
		lines = [[NSMutableArray alloc] init];
		_finished = NO;
		last_begin_time = last_end_time = 0;
		linesInput = 0;
	}
	
	return self;
}

static CFComparisonResult CompareLinesByBeginTime(const void *a, const void *b, void *unused)
{
	MP42SubLine *al = (__bridge MP42SubLine *)a, *bl = (__bridge MP42SubLine *)b;
	
	if (al->begin_time > bl->begin_time) return kCFCompareGreaterThan;
	if (al->begin_time < bl->begin_time) return kCFCompareLessThan;
	
	if (al->no > bl->no) return kCFCompareGreaterThan;
	if (al->no < bl->no) return kCFCompareLessThan;
	return kCFCompareEqualTo;
}

-(void)addLine:(MP42SubLine *)line
{
	if (line->begin_time >= line->end_time) {
		if (line->begin_time)
			//Codecprintf(NULL, "Invalid times (%d and %d) for line \"%s\"", line->begin_time, line->end_time, [line->line UTF8String]);
		return;
	}
	
	line->no = linesInput++;
	
	NSUInteger nlines = lines.count;
	
	if (!nlines || line->begin_time > ((MP42SubLine*)[lines objectAtIndex:nlines-1])->begin_time) {
		[lines addObject:line];
	} else {
		CFIndex i = CFArrayBSearchValues((CFArrayRef)lines, CFRangeMake(0, nlines), (__bridge const void *)(line), CompareLinesByBeginTime, NULL);

		if (i >= nlines)
			[lines addObject:line];
		else
			[lines insertObject:line atIndex:i];
	}
	
}

-(MP42SubLine *)getNextRealSerializedPacket
{
	NSUInteger nlines = [lines count];
	MP42SubLine *first = [lines objectAtIndex:0];
    NSMutableString *str;
    NSUInteger i;
    
    if (!_finished) {
		if (nlines > 1) {
            uint64_t maxEndTime = first->end_time;
			
			for (i = 1; i < nlines; i++) {
				MP42SubLine *l = [lines objectAtIndex:i];
				
				if (l->begin_time >= maxEndTime) {
					goto canOutput;
				}
				
				maxEndTime = MAX(maxEndTime, l->end_time);
			}
		}
		
		return nil;
	}

canOutput:
	str = [NSMutableString stringWithString:first->line];
    uint64_t begin_time = last_end_time, end_time = first->end_time;
    unsigned frcd = first->forced, top_pos = first->top;
	int deleted = 0;
    
	for (i = 1; i < nlines; i++) {
		MP42SubLine *l = [lines objectAtIndex:i];
		if (l->begin_time >= end_time) break;
		
		//shorten packet end time if another shorter time (begin or end) is found
		//as long as it isn't the begin time
		end_time = MIN(end_time, l->end_time);
		if (l->begin_time > begin_time)
			end_time = MIN(end_time, l->begin_time);
		
        if (l->begin_time <= begin_time) {
            // Try to be a bit smart and avoid duplicated lines
            // from ssa.
            if (!_ssa || [str rangeOfString:l->line].location == NSNotFound) {
                [str appendString:l->line];
            }
        }
	}
	
	for (i = 0; i < nlines; i++) {
		MP42SubLine *l = [lines objectAtIndex:i - deleted];
		
		if (l->end_time == end_time) {
			[lines removeObjectAtIndex:i - deleted];
			deleted++;
		}
	}
	
	return [[MP42SubLine alloc] initWithLine:str start:begin_time end:end_time top_pos:top_pos forced:frcd];
}

-(MP42SubLine*)getSerializedPacket
{
	NSUInteger nlines = [lines count];
    
	if (!nlines) return nil;
	
	MP42SubLine *nextline = [lines objectAtIndex:0], *ret;
	
	if (nextline->begin_time > last_end_time) {
		ret = [[MP42SubLine alloc] initWithLine:@"\n" start:last_end_time end:nextline->begin_time];
	} else {
		ret = [self getNextRealSerializedPacket];
	}
	
	if (!ret) return nil;
	
	last_begin_time = ret->begin_time;
	last_end_time   = ret->end_time;
    
	return ret;
}

-(BOOL)isEmpty
{
	return [lines count] == 0;
}


-(NSString *)description
{
    return [NSString stringWithFormat:@"lines left: %lu finished inputting: %d",(unsigned long)[lines count],_finished];
}

@end

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42SubLine

-(instancetype)initWithLine:(NSString *)l start:(uint64_t)s end:(uint64_t)e
{
	if ((self = [super init])) {
		if ([l characterAtIndex:[l length]-1] != '\n') l = [l stringByAppendingString:@"\n"];
		line = l;
		begin_time = s;
		end_time = e;
		no = 0;
	}
	
	return self;
}

-(id)initWithLine:(NSString*)l start:(uint64_t)s end:(uint64_t)e top_pos:(unsigned)p forced:(unsigned)f
{
	if ((self = [self initWithLine:l start:s end:e])) {
        top = p;
        forced = f;
	}
	
	return self;
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"\"%@\", from %llu s to %llu s",[line substringToIndex:line.length -1] ,begin_time, end_time];
}

@end

unsigned ParseSubTime(const char *time, unsigned secondScale, BOOL hasSign)
{
	unsigned hour, minute, second, subsecond, timeval;
	char separator[3];
	int sign = 1;

	if (hasSign && *time == '-') {
		sign = -1;
		time++;
	}

    if (sscanf(time, "%u:%u:%u%[,.:]%u", &hour, &minute, &second, separator, &subsecond) < 5) {
        subsecond = 0;
        if (sscanf(time, "%u:%u:%u", &hour, &minute, &second) < 3) {
            return 0;
        }
    }

    if (second > 60) {
        second = 0;
    }

    while (subsecond > secondScale) {
        subsecond /= 10;
    }

	timeval = hour * 60 * 60 + minute * 60 + second;
	timeval = secondScale * timeval + subsecond;

	return timeval * sign;
}

NSMutableString *STStandardizeStringNewlines(NSString *str)
{
    if(str == nil)
		return nil;
	NSMutableString *ms = [NSMutableString stringWithString:str];
	[ms replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0,[ms length])];
	[ms replaceOccurrencesOfString:@"\r" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0,[ms length])];
	return ms;
}

extern NSString *STLoadFileWithUnknownEncoding(NSURL *url)
{
	NSData *data = [NSData dataWithContentsOfURL:url];

    if (!data) {
        return nil;
    }

	NSString *res = nil;
	NSStringEncoding enc;

    BOOL lossy = NO;
    enc = [NSString stringEncodingForData:data
                          encodingOptions:nil
                          convertedString:&res
                      usedLossyConversion:&lossy];


    if (res && lossy == NO) {
        NSLog(@"Guessed encoding %lu.\n", (unsigned long)enc);
        return res;
    } else if (res) {
        NSLog(@"Guessed encoding %lu, lossy convertion\n", (unsigned long)enc);
        return res;
    } else {
        return nil;
    }
}

static int ParsePosition(NSString *str)
{
	NSScanner *sc = [NSScanner scannerWithString:str];

	int res = INT_MAX;

	if ([sc scanUpToString:@"X1:" intoString:nil]) {
        [sc scanString:@"X1:" intoString:nil];
		[sc scanInt:&res];
    }

	return res;
}

static int ParseForced(NSString *str)
{
    NSRange s = [str rangeOfString:@"!!!"];    
	int res = 0;
    
	if (s.location != NSNotFound)
        res = 1;
    
	return res;
}

int LoadSRTFromURL(NSURL *url, MP42SubSerializer *ss, MP4Duration *duration)
{
	NSMutableString *srt = STStandardizeStringNewlines(STLoadFileWithUnknownEncoding(url));
	if (!srt.length) return 0;

	if ([srt characterAtIndex:0] == 0xFEFF) [srt deleteCharactersInRange:NSMakeRange(0,1)];
	if ([srt characterAtIndex:[srt length]-1] != '\n') [srt appendFormat:@"%c",'\n'];

	NSScanner *sc = [NSScanner scannerWithString:srt];
	NSString *res = nil;
	[sc setCharactersToBeSkipped:nil];

	unsigned startTime = 0, endTime = 0, forced = 0;
    unsigned posCount = 0, forcedCount = 0;
    signed position = INT_MAX;

	enum {
		INITIAL,
		TIMESTAMP,
		LINES
	} state = INITIAL;

	do {
		switch (state) {
			case INITIAL:
				if ([sc scanInt:NULL] == TRUE && [sc scanUpToString:@"\n" intoString:&res] == FALSE) {
					state = TIMESTAMP;
					[sc scanString:@"\n" intoString:nil];
				} else
					[sc setScanLocation:[sc scanLocation]+1];
				break;
			case TIMESTAMP:
				[sc scanUpToString:@" --> " intoString:&res];
				[sc scanString:@" --> " intoString:nil];
				startTime = ParseSubTime([res UTF8String], 1000, NO);

				[sc scanUpToString:@"\n" intoString:&res];
				[sc scanString:@"\n" intoString:nil];
				endTime = ParseSubTime([res UTF8String], 1000, NO);
                position = ParsePosition(res);
                forced = ParseForced(res);
                if (position < INT_MAX)
                    posCount++;
                if (forced)
                    forcedCount++;

				state = LINES;
				break;
			case LINES:
				[sc scanUpToString:@"\n\n" intoString:&res];
				[sc scanString:@"\n\n" intoString:nil];
				MP42SubLine *sl = [[MP42SubLine alloc] initWithLine:res start:startTime end:endTime top_pos:position forced:forced];
				[ss addLine:sl];
				state = INITIAL;
				break;
		};
	} while (![sc isAtEnd]);

    if (posCount)
        [ss setPositionInformation:YES];
    if (forcedCount) {
        [ss setForced:YES];
    }

    *duration = endTime;

    return 1;
}

int LoadChaptersFromURL(NSURL *url, NSMutableArray *ss)
{
	NSMutableString *srt = STStandardizeStringNewlines(STLoadFileWithUnknownEncoding(url));
	if (!srt) return 0;

	if ([srt characterAtIndex:0] == 0xFEFF) [srt deleteCharactersInRange:NSMakeRange(0,1)];
	if ([srt characterAtIndex:[srt length]-1] != '\n') [srt appendFormat:@"%c",'\n'];

    NSScanner *sc = [NSScanner scannerWithString:srt];
	NSString *res=nil;
	[sc setCharactersToBeSkipped:nil];

	unsigned time=0;
    int count = 1;
	enum {
		TIMESTAMP,
		LINES
	} state = TIMESTAMP;

    if ([srt characterAtIndex:0] == 'C') { // ogg tools format
        do {
            switch (state) {
                case TIMESTAMP:
                    [sc scanUpToString:@"=" intoString:nil];
                    [sc scanString:@"=" intoString:nil];
                    [sc scanUpToString:@"\n" intoString:&res];
                    [sc scanString:@"\n" intoString:nil];
                    time = ParseSubTime([res UTF8String], 1000, NO);

                    state = LINES;
                    break;
                case LINES:
                    [sc scanUpToString:@"=" intoString:nil];
                    [sc scanString:@"=" intoString:nil];
                    if (!([sc scanUpToString:@"\n" intoString:&res]))
                        res = [NSString stringWithFormat:@"Chapter %d", count];
                    [sc scanString:@"\n" intoString:nil];

                    MP42TextSample *chapter = [[MP42TextSample alloc] init];
                    chapter.timestamp = time;
                    chapter.title = res;

                    [ss addObject:chapter];
                    count++;

                    state = TIMESTAMP;
                    break;
            };
        } while (![sc isAtEnd]);
    }
    else  //mp4chaps format
    {
        do {
            switch (state) {
                case TIMESTAMP:
                    [sc scanUpToString:@" " intoString:&res];
                    [sc scanString:@" " intoString:nil];
                    time = ParseSubTime([res UTF8String], 1000, NO);

                    state = LINES;
                    break;
                case LINES:
                    if (!([sc scanUpToString:@"\n" intoString:&res]))
                        res = [NSString stringWithFormat:@"Chapter %d", count];

                    [sc scanString:@"\n" intoString:nil];

                    MP42TextSample *chapter = [[MP42TextSample alloc] init];
                    chapter.timestamp = time;
                    chapter.title = res;
                    
                    [ss addObject:chapter];
                    count++;

                    state = TIMESTAMP;
                    break;
            };
        } while (![sc isAtEnd]);
    }
    
    return 1;
}

static int parse_SYNC(NSString *str)
{
	NSScanner *sc = [NSScanner scannerWithString:str];
    
	int res = 0;
    
	if ([sc scanString:@"START=" intoString:nil])
		[sc scanInt:&res];
    
	return res;
}

static NSArray *parse_STYLE(NSString *str)
{
	NSScanner *sc = [NSScanner scannerWithString:str];
    
	NSString *firstRes;
	NSString *secondRes;
	NSArray *subArray;
	int secondLoc;
    
	[sc scanUpToString:@"<P CLASS=" intoString:nil];
	if ([sc scanString:@"<P CLASS=" intoString:nil])
		[sc scanUpToString:@">" intoString:&firstRes];
	else
		firstRes = @"noClass";
    
	secondLoc = [str length] * .9;
	[sc setScanLocation:secondLoc];
    
	[sc scanUpToString:@"<P CLASS=" intoString:nil];
	if ([sc scanString:@"<P CLASS=" intoString:nil])
		[sc scanUpToString:@">" intoString:&secondRes];
	else
		secondRes = @"noClass";
    
	if ([firstRes isEqualToString:secondRes])
		secondRes = @"noClass";
    
	subArray = [NSArray arrayWithObjects:firstRes, secondRes, nil];
    
	return subArray;
}

static int parse_P(NSString *str, NSArray *subArray)
{
	NSScanner *sc = [NSScanner scannerWithString:str];
    
	NSString *res;
	int subLang;
    
	if ([sc scanString:@"CLASS=" intoString:nil])
		[sc scanUpToString:@">" intoString:&res];
	else
		res = @"noClass";
    
	if ([res isEqualToString:[subArray objectAtIndex:0]])
		subLang = 1;
	else if ([res isEqualToString:[subArray objectAtIndex:1]])
		subLang = 2;
	else
		subLang = 3;
    
	return subLang;
}

static NSString *parse_COLOR(NSString *str)
{
	NSString *cvalue;
	NSMutableString *cname = [NSMutableString stringWithString:str];
    
	if (![str length]) return str;
	
	if ([cname characterAtIndex:0] == '#' && [cname lengthOfBytesUsingEncoding:NSASCIIStringEncoding] == 7)
		cvalue = [NSString stringWithFormat:@"{\\1c&H%@%@%@&}", [cname substringWithRange:NSMakeRange(5,2)], [cname substringWithRange:NSMakeRange(3,2)], [cname substringWithRange:NSMakeRange(1,2)]];
	else {
		[cname replaceOccurrencesOfString:@"Aqua" withString:@"00FFFF" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Black" withString:@"000000" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Blue" withString:@"0000FF" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Fuchsia" withString:@"FF00FF" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Gray" withString:@"808080" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Green" withString:@"008000" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Lime" withString:@"00FF00" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Maroon" withString:@"800000" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Navy" withString:@"000080" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Olive" withString:@"808000" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Purple" withString:@"800080" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Red" withString:@"FF0000" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Silver" withString:@"C0C0C0" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Teal" withString:@"008080" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"White" withString:@"FFFFFF" options:1 range:NSMakeRange(0,[cname length])];
		[cname replaceOccurrencesOfString:@"Yellow" withString:@"FFFF00" options:1 range:NSMakeRange(0,[cname length])];
        
		if ([cname lengthOfBytesUsingEncoding:NSASCIIStringEncoding] == 6)
			cvalue = [NSString stringWithFormat:@"{\\1c&H%@%@%@&}", [cname substringWithRange:NSMakeRange(4,2)], [cname substringWithRange:NSMakeRange(2,2)], [cname substringWithRange:NSMakeRange(0,2)]];
		else
			cvalue = @"{\\1c&HFFFFFF&}";
	}
    
	return cvalue;
}

static NSString *parse_FONT(NSString *str)
{
	NSScanner *sc = [NSScanner scannerWithString:str];
    
	NSString *res;
	NSString *color;
    
	if ([sc scanString:@"COLOR=" intoString:nil]) {
		[sc scanUpToString:@">" intoString:&res];
		color = parse_COLOR(res);
	}
	else
		color = @"{\\1c&HFFFFFF&}";
    
	return color;
}

static NSMutableString *StandardizeSMIWhitespace(NSString *str)
{
	if (!str) return nil;
	NSMutableString *ms = [NSMutableString stringWithString:str];
	[ms replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0,[ms length])];
	[ms replaceOccurrencesOfString:@"\n" withString:@"" options:0 range:NSMakeRange(0,[ms length])];
	[ms replaceOccurrencesOfString:@"&nbsp;" withString:@" " options:0 range:NSMakeRange(0,[ms length])];
	return ms;
}

int LoadSMIFromURL(NSURL *url, MP42SubSerializer *ss, int subCount)
{
	NSMutableString *smi = StandardizeSMIWhitespace(STLoadFileWithUnknownEncoding(url));
	if (!smi) return 0;
    
	NSScanner *sc = [NSScanner scannerWithString:smi];
	NSString *res = nil;
	[sc setCharactersToBeSkipped:nil];
	[sc setCaseSensitive:NO];
	
	NSMutableString *cmt = [NSMutableString string];
	NSArray *subLanguage = parse_STYLE(smi);
    
	int startTime=-1, endTime=-1, syncTime=-1;
	int cc=1;
	
	enum {
		TAG_INIT,
		TAG_SYNC,
		TAG_P,
		TAG_BR_OPEN,
		TAG_BR_CLOSE,
		TAG_B_OPEN,
		TAG_B_CLOSE,
		TAG_I_OPEN,
		TAG_I_CLOSE,
		TAG_FONT_OPEN,
		TAG_FONT_CLOSE,
		TAG_COMMENT
	} state = TAG_INIT;
	
	do {
		switch (state) {
			case TAG_INIT:
				[sc scanUpToString:@"<SYNC" intoString:nil];
				if ([sc scanString:@"<SYNC" intoString:nil])
					state = TAG_SYNC;
				break;
			case TAG_SYNC:
				[sc scanUpToString:@">" intoString:&res];
				syncTime = parse_SYNC(res);
				if (startTime > -1) {
					endTime = syncTime;
					if (subCount == 2 && cc == 2)
						[cmt insertString:@"{\\an8}" atIndex:0];
					if ((subCount == 1 && cc == 1) || (subCount == 2 && cc == 2)) {
						MP42SubLine *sl = [[MP42SubLine alloc] initWithLine:cmt start:startTime end:endTime];
						[ss addLine:sl];
					}
				}
				startTime = syncTime;
				[cmt setString:@""];
				state = TAG_COMMENT;
				break;
			case TAG_P:
				[sc scanUpToString:@">" intoString:&res];
				cc = parse_P(res, subLanguage);
				[cmt setString:@""];
				state = TAG_COMMENT;
				break;
			case TAG_BR_OPEN:
				[sc scanUpToString:@">" intoString:nil];
				[cmt appendString:@"\\n"];
				state = TAG_COMMENT;
				break;
			case TAG_BR_CLOSE:
				[sc scanUpToString:@">" intoString:nil];
				[cmt appendString:@"\\n"];
				state = TAG_COMMENT;
				break;
			case TAG_B_OPEN:
				[sc scanUpToString:@">" intoString:&res];
				[cmt appendString:@"{\\b1}"];
				state = TAG_COMMENT;
				break;
			case TAG_B_CLOSE:
				[sc scanUpToString:@">" intoString:nil];
				[cmt appendString:@"{\\b0}"];
				state = TAG_COMMENT;
				break;
			case TAG_I_OPEN:
				[sc scanUpToString:@">" intoString:&res];
				[cmt appendString:@"{\\i1}"];
				state = TAG_COMMENT;
				break;
			case TAG_I_CLOSE:
				[sc scanUpToString:@">" intoString:nil];
				[cmt appendString:@"{\\i0}"];
				state = TAG_COMMENT;
				break;
			case TAG_FONT_OPEN:
				[sc scanUpToString:@">" intoString:&res];
				[cmt appendString:parse_FONT(res)];
				state = TAG_COMMENT;
				break;
			case TAG_FONT_CLOSE:
				[sc scanUpToString:@">" intoString:nil];
				[cmt appendString:@"{\\1c&HFFFFFF&}"];
				state = TAG_COMMENT;
				break;
			case TAG_COMMENT:
				[sc scanString:@">" intoString:nil];
				if ([sc scanUpToString:@"<" intoString:&res])
					[cmt appendString:res];
				else
					[cmt appendString:@"<>"];
				if ([sc scanString:@"<" intoString:nil]) {
					if ([sc scanString:@"SYNC" intoString:nil]) {
						state = TAG_SYNC;
						break;
					}
					else if ([sc scanString:@"P" intoString:nil]) {
						state = TAG_P;
						break;
					}
					else if ([sc scanString:@"BR" intoString:nil]) {
						state = TAG_BR_OPEN;
						break;
					}
					else if ([sc scanString:@"/BR" intoString:nil]) {
						state = TAG_BR_CLOSE;
						break;
					}
					else if ([sc scanString:@"B" intoString:nil]) {
						state = TAG_B_OPEN;
						break;
					}
					else if ([sc scanString:@"/B" intoString:nil]) {
						state = TAG_B_CLOSE;
						break;
					}
					else if ([sc scanString:@"I" intoString:nil]) {
						state = TAG_I_OPEN;
						break;
					}
					else if ([sc scanString:@"/I" intoString:nil]) {
						state = TAG_I_CLOSE;
						break;
					}
					else if ([sc scanString:@"FONT" intoString:nil]) {
						state = TAG_FONT_OPEN;
						break;
					}
					else if ([sc scanString:@"/FONT" intoString:nil]) {
						state = TAG_FONT_CLOSE;
						break;
					}
					else {
						[cmt appendString:@"<"];
						state = TAG_COMMENT;
						break;
					}
				}
		}
	} while (![sc isAtEnd]);
    return 1;
}

u_int8_t * createStyleRecord(u_int16_t startChar, u_int16_t endChar, u_int16_t fontID, u_int8_t flags, rgba_color color, u_int8_t* style, u_int8_t fontSize)
{
    style[0] = (startChar >> 8) & 0xff; // startChar
    style[1] = startChar & 0xff;
    style[2] = (endChar >> 8) & 0xff;   // endChar
    style[3] = endChar & 0xff;
    style[4] = (fontID >> 8) & 0xff;    // font-ID
    style[5] = fontID & 0xff;
    style[6] = flags;            // face-style-flags: 1 bold; 2 italic; 4 underline
    style[7] = fontSize;         // font-size
    style[8] = color.r;          // r
    style[9] = color.g;          // g
    style[10] = color.b;         // b
    style[11] = color.a;         // a

    return style;
}

size_t closeStyleAtom(u_int16_t styleCount, u_int8_t* styleAtom)
{
    size_t styleSize = 10 + (styleCount * 12);
    styleAtom[0] = 0;
    styleAtom[1] = 0;
    styleAtom[2] = (styleSize >> 8) & 0xff;
    styleAtom[3] = styleSize & 0xff;
    styleAtom[8] = (styleCount >> 8) & 0xff;
    styleAtom[9] = styleCount & 0xff;
    
    return styleSize;
}

NSString * createStyleAtomForString(NSString *string, u_int8_t fontSize, u_int8_t **buffer, size_t *size)
{
    MP42HtmlParser *parser = [[MP42HtmlParser alloc] initWithString:string];
    parser.defaultColor = make_color(255, 255, 255, 255);

    while ([parser parseNextTag] != NSNotFound);

    [parser serializeStyles];

    *buffer = malloc(sizeof(u_int8_t) * 12 * [parser.styles count] + 10);
    u_int16_t styleCount = 0;
    memcpy(*buffer + 4, "styl", 4);

    for (MP42Style *style in parser.styles) {
        u_int8_t styleRecord[12];
        createStyleRecord(style.location, style.location + style.length, 1, style.style, style.color, styleRecord, fontSize);
        memcpy(*buffer + 10 + (12 * styleCount), styleRecord, 12);
        styleCount++;
    }

    if (styleCount) {
        *size = closeStyleAtom(styleCount, *buffer);
    }

    return parser.text;
}

NSString* removeNewLines(NSString* string) {
    NSMutableString *mutableString = [NSMutableString stringWithString:string];

	[mutableString replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0,[mutableString length])];
	[mutableString replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0,[mutableString length])];

    while ([mutableString length] && [mutableString characterAtIndex:[mutableString length] - 1] == '\n') {
        [mutableString deleteCharactersInRange:NSMakeRange([mutableString length] -1, 1)];
    }

    return mutableString;
}

void createForcedAtom(u_int8_t* buffer) {
    buffer[0] = 0;
    buffer[1] = 0;
    buffer[2] = 0;
    buffer[3] = 8;
    buffer[4] = 'f';
    buffer[5] = 'r';
    buffer[6] = 'c';
    buffer[7] = 'd';
}

void createTboxAtom(u_int8_t* buffer, u_int16_t top, u_int16_t left, u_int16_t bottom, u_int16_t right) {
    buffer[0] = 0;
    buffer[1] = 0;
    buffer[2] = 0;
    buffer[3] = 16;
    buffer[4] = 't';
    buffer[5] = 'b';
    buffer[6] = 'o';
    buffer[7] = 'x';
    buffer[8] = top >> 8;
    buffer[9] = top & 0xFF;
    buffer[10] = left >> 8;
    buffer[11] = left & 0xFF;
    buffer[12] = bottom >> 8;
    buffer[13] = bottom & 0xFF;
    buffer[14] = right >> 8;
    buffer[15] = right & 0xFF;
}

MP42SampleBuffer * copySubtitleSample(MP4TrackId subtitleTrackId, NSString *string, MP4Duration duration, BOOL forced, BOOL verticalPlacement, BOOL styles, CGSize trackSize, int top)
{
    u_int8_t *sampleData = NULL, *styleAtom = NULL;
    size_t styleSize = 0, sampleSize = 0, stringLength = 0;
    u_int64_t pos = 0;

    u_int8_t fontSize = verticalPlacement ? trackSize.height * 0.05 : trackSize.height / 0.15 * 0.05;

    string = removeNewLines(string);
    if (styles) {
        string = createStyleAtomForString(string, fontSize, &styleAtom, &styleSize);
    }

    stringLength = strlen(string.UTF8String);
    sampleSize = 2 + (stringLength * sizeof(char)) + styleSize + (forced == 1 ? 8 : 0) + (verticalPlacement == 1 ? 16 : 0);

    if (sampleSize > UINT16_MAX)
    {
        // Too big for a tx3g sample
        free(styleAtom);
        return copyEmptySubtitleSample(subtitleTrackId, duration, forced);
    }

    sampleData = malloc(sampleSize);

    pos = 2;

    if (stringLength) {
        memcpy(sampleData + pos, string.UTF8String, stringLength);
        pos += stringLength;
    }

    if (styleSize) {
        memcpy(sampleData + pos, styleAtom, styleSize);
        pos += styleSize;
    }

    // Add a frcd atom
    if (forced) {
        u_int8_t forcedAtom[8];
        createForcedAtom(forcedAtom);

        memcpy(sampleData + pos, forcedAtom, 8);
        pos += 8;
    }

    // Add a tbox atom with offset from top
    if (verticalPlacement) {
        u_int8_t tboxAtom[16];
        if (top == 0) {
            createTboxAtom(tboxAtom, top, 0, trackSize.height * 0.12, trackSize.width);
        } else {
            createTboxAtom(tboxAtom, trackSize.height * 0.88, 0, trackSize.height, trackSize.width);
        }

        memcpy(sampleData + pos, tboxAtom, 16);
    }

    sampleData[0] = (stringLength >> 8) & 0xff;
    sampleData[1] = stringLength & 0xff;

    free(styleAtom);

    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
    sample->data = sampleData;
    sample->size = (uint32_t)sampleSize;
    sample->duration = duration;
    sample->offset = 0;
    sample->decodeTimestamp = duration;
    sample->flags |= MP42SampleBufferFlagIsSync;
    sample->trackId = subtitleTrackId;

    return sample;
}

MP42SampleBuffer * copyEmptySubtitleSample(MP4TrackId subtitleTrackId, MP4Duration duration, BOOL forced)
{
    uint8_t *sampleData = NULL;
    size_t sampleSize = 0;

    u_int8_t empty[2] = {0,0};

    sampleSize = 2 + (forced == 1 ? 8 : 0);
    sampleData = malloc(sampleSize);
    memcpy(sampleData, empty, 2);

    // Add a frcd atom
    if (forced) {
        u_int8_t forcedAtom[8];
        createForcedAtom(forcedAtom);

        memcpy(sampleData + 2, forcedAtom, 8);
    }

    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
    sample->data = sampleData;
    sample->size = 2;
    sample->duration = duration;
    sample->offset = 0;
    sample->decodeTimestamp = duration;
    sample->flags |= MP42SampleBufferFlagIsSync;
    sample->trackId = subtitleTrackId;

    return sample;
}

/* VobSub related */
int ExtractVobSubPacket(UInt8 *dest, UInt8 *framedSrc, long srcSize, int * _Nullable usedSrcBytes, int index) {
	int copiedBytes = 0;
	UInt8 *currentPacket = framedSrc;
	int packetSize = INT_MAX;
	
	while (currentPacket - framedSrc < srcSize && copiedBytes < packetSize) {
		// 3-byte start code: 0x00 00 01
		if (currentPacket[0] + currentPacket[1] != 0 || currentPacket[2] != 1) {
			//Codecprintf(NULL, "VobSub Codec: !! Unknown header: %02x %02x %02x\n", currentPacket[0], currentPacket[1], currentPacket[2]);
			return copiedBytes;
		}
		
		int packet_length;
		
		switch (currentPacket[3]) {
			case 0xba:
				// discard PS packets; nothing in them we're interested in
				// here, packet_length is the additional stuffing
				packet_length = currentPacket[13] & 0x7;
				
				currentPacket += 14 + packet_length;
				break;
				
			case 0xbe:
			case 0xbf:
				// skip padding and navigation data
				// (navigation shouldn't be present anyway)
				packet_length = currentPacket[4];
				packet_length <<= 8;
				packet_length += currentPacket[5];
				
				currentPacket += 6 + packet_length;
				break;
				
			case 0xbd:
				// a private stream packet, contains subtitle data
				packet_length = currentPacket[4];
				packet_length <<= 8;
				packet_length += currentPacket[5];
				
				int header_data_length = currentPacket[8];
				int packetIndex = currentPacket[header_data_length + 9] & 0x1f;
                if (index == -1) {
					index = packetIndex;
                }
				if (index == packetIndex) {
					int blockSize = packet_length - 1 - (header_data_length + 3);
					memcpy(&dest[copiedBytes],
						   // header's 9 bytes + extension, we don't want 1st byte of packet
						   &currentPacket[9 + header_data_length + 1],
						   // we don't want the 1-byte stream ID, or the header
						   blockSize);
					copiedBytes += blockSize;
                    
					if (packetSize == INT_MAX) {
						packetSize = dest[0] << 8 | dest[1];
					}
				}
				currentPacket += packet_length + 6;
				break;
				
			default:
				// unknown packet, probably video, return for now
				//Codecprintf(NULL, "VobSubCodec - Unknown packet type %x, aborting\n", (int)currentPacket[3]);
				return copiedBytes;
		} // switch (currentPacket[3])
	} // while (currentPacket - framedSrc < srcSize)
    if (usedSrcBytes != NULL) {
		*usedSrcBytes = (int)(currentPacket - framedSrc);
    }

	return copiedBytes;
}

ComponentResult ReadPacketControls(UInt8 *packet, UInt32 palette[16], PacketControlData *controlDataOut,BOOL *forced) {
	// to set whether the key sequences 0x03 - 0x06 have been seen
	UInt16 controlSeqSeen = 0;
	int i = 0;
	Boolean loop = TRUE;
	int controlOffset = (packet[2] << 8) + packet[3] + 4;
	uint8_t *controlSeq = packet + controlOffset;

	memset(controlDataOut, 0, sizeof(PacketControlData));

	while (loop) {
		switch (controlSeq[i]) {
			case 0x00:
				// subpicture identifier, we don't care
                *forced = YES;
				i++;
				break;
				
			case 0x01:
				// start displaying, we don't care
				i++;
				break;
				
			case 0x03:
				// palette info
				controlDataOut->pixelColor[3] += palette[controlSeq[i+1] >> 4 ];
				controlDataOut->pixelColor[2] += palette[controlSeq[i+1] & 0xf];
				controlDataOut->pixelColor[1] += palette[controlSeq[i+2] >> 4 ];
				controlDataOut->pixelColor[0] += palette[controlSeq[i+2] & 0xf];
				
				i += 3;
				controlSeqSeen |= 0x0f;
				break;
				
			case 0x04:
				// alpha info
				controlDataOut->pixelColor[3] += (controlSeq[i + 1] & 0xf0) << 20;
				controlDataOut->pixelColor[2] += (controlSeq[i + 1] & 0x0f) << 24;
				controlDataOut->pixelColor[1] += (controlSeq[i + 2] & 0xf0) << 20;
				controlDataOut->pixelColor[0] += (controlSeq[i + 2] & 0x0f) << 24;
				
				// double the nibble
				controlDataOut->pixelColor[3] += (controlSeq[i + 1] & 0xf0) * 1u << 24;
				controlDataOut->pixelColor[2] += (controlSeq[i + 1] & 0x0f) * 1u << 28;
				controlDataOut->pixelColor[1] += (controlSeq[i + 2] & 0xf0) * 1u << 24;
				controlDataOut->pixelColor[0] += (controlSeq[i + 2] & 0x0f) * 1u << 28;
				
				i += 3;
				controlSeqSeen |= 0xf0;
				break;
				
			case 0x05:
				// coordinates of image, ffmpeg takes care of this
				i += 7;
				break;
				
			case 0x06:
				// offset of the first graphic line, and second, ffmpeg takes care of this
				i += 5;
				break;
				
			case 0xff:
				// end of control sequence
				loop = FALSE;
				break;
				
			default:
				NSLog(@"!! Unknown control sequence 0x%02x  aborting (offset %x)\n", controlSeq[i], i);
				loop = FALSE;
				break;
		}
	}
	
	// force fully transparent to transparent black; needed? for graphicsModePreBlackAlpha
	for (i = 0; i < 4; i++) {
        if ((controlDataOut->pixelColor[i] & 0xff000000) == 0) {
			controlDataOut->pixelColor[i] = 0;
        }
	}
	
    if (controlSeqSeen != 0xff) {
		return -1;
    }
	return noErr;
}

Boolean ReadPacketTimes(uint8_t *packet, uint32_t length, uint16_t *startTime, uint16_t *endTime, uint8_t *forced) {
	// to set whether the key sequences 0x01 - 0x02 have been seen
	Boolean loop = TRUE;
	*startTime = *endTime = 0;
	*forced = 0;
    
	int controlOffset = (packet[2] << 8) + packet[3];
	while(loop)
	{
        if (controlOffset > length) {
			return NO;
        }
		uint8_t *controlSeq = packet + controlOffset;
		int32_t i = 4;
		int32_t end = length - controlOffset;
		uint16_t timestamp = (controlSeq[0] << 8) | controlSeq[1];
		uint16_t nextOffset = (controlSeq[2] << 8) + controlSeq[3];
		while (i < end) {
			switch (controlSeq[i]) {
				case 0x00:
					*forced = 1;
					i++;
					break;
					
				case 0x01:
					*startTime = (timestamp << 10) / 90;
					i++;
					break;
                    
				case 0x02:
					*endTime = (timestamp << 10) / 90;
					i++;
					loop = false;
					break;
					
				case 0x03:
					// palette info, we don't care
					i += 3;
					break;
					
				case 0x04:
					// alpha info, we don't care
					i += 3;
					break;
					
				case 0x05:
					// coordinates of image, ffmpeg takes care of this
					i += 7;
					break;
					
				case 0x06:
					// offset of the first graphic line, and second, ffmpeg takes care of this
					i += 5;
					break;
					
				case 0xff:
					// end of control sequence
					if(controlOffset == nextOffset)
						loop = false;
					controlOffset = nextOffset;
					i = INT_MAX;
					break;
					
				default:
					return NO;
			}
		}
		if(i != INT_MAX)
		{
			//End of packet
			loop = false;
		}
	}
	return YES;
}
