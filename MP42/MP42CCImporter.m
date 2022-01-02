//
//  MP42CCImporter.m
//  Subler
//
//  Created by Damiano Galassi on 05/12/10.
//  Copyright 2022 Damiano Galassi All rights reserved.
//

#import "MP42CCImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42SubUtilities.h"
#import "MP42Languages.h"
#import "MP42File.h"
#import "MP42SampleBuffer.h"
#import "NSString+MP42Additions.h"
#import "MP42Track+Private.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42CCImporter

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"scc"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError * __autoreleasing *)outError
{
    if ((self = [super initWithURL:fileURL])) {
        MP42Track *newTrack = [[MP42ClosedCaptionTrack alloc] init];

        newTrack.format = kMP42ClosedCaptionCodecType_CEA608;
        newTrack.URL = self.fileURL;
        newTrack.timescale = 30000;

        [self addTrack:newTrack];
    }

    return self;
}

- (nullable NSData *)magicCookieForTrack:(MP42Track *)track
{
    return nil;
}

static unsigned ParseTimeCode(const char *time, unsigned secondScale, BOOL hasSign, uint64_t *dropFrame)
{
	unsigned hour, minute, second, frame, timeval;
	char separator;
	int sign = 1;

	if (hasSign && *time == '-') {
		sign = -1;
		time++;
	}

    if (sscanf(time,"%u:%u:%u%[,.:;]%u",&hour,&minute,&second,&separator,&frame) < 5) {
		return 0;
    }

	timeval = (hour * 60 * 60 + minute * 60 + second) * 30 + frame;
	//timeval = secondScale * timeval + frame;

    if (separator == ';') {
        *dropFrame = 1;
    }

	return timeval * sign;
}

static int ParseByte(const char *string, UInt8 *byte, Boolean hex)
{
	int err = 0;
	char chars[2];
    
	if (sscanf(string, "%2c", chars) == 1)
	{
		chars[0] = (char)tolower(chars[0]);
		chars[1] = (char)tolower(chars[1]);
        
		if (((chars[0] >= '0' && chars[0] <= '9') || (hex && (chars[0] >= 'a' && chars[0] <= 'f'))) &&
			((chars[1] >= '0' && chars[1] <= '9') || (hex && (chars[1] >= 'a' && chars[1] <= 'f'))))
		{
			*byte = 0;
			if (chars[0] >= '0' && chars[0] <= '9')
				*byte = (chars[0] - '0') * (hex ? 16 : 10);
			else if (chars[0] >= 'a' && chars[0] <= 'f')
				*byte = (chars[0] - 'a' + 10) * 16;
			
			if (chars[1] >= '0' && chars[1] <= '9')
				*byte += (chars[1] - '0');
			else if (chars[1] >= 'a' && chars[1] <= 'f')
				*byte += (chars[1] - 'a' + 10);
			
			err = 1;
		}
	}
    
	return err;
}

- (void)demux
{
    @autoreleasepool {
        MP4TrackId trackId = self.inputTracks.lastObject.sourceId;

        NSString *scc = STStandardizeStringNewlines(STLoadFileWithUnknownEncoding(self.fileURL));
        if (!scc) { return; }

        NSScanner *sc = [NSScanner scannerWithString:scc];
        NSString *res = nil;
        [sc setCharactersToBeSkipped:nil];

        [sc scanUpToString:@"\n" intoString:&res];
        if (![res isEqualToString:@"Scenarist_SCC V1.0"]) {
            return;
        }

        unsigned startTime=0;
        BOOL firstSample = YES;
        NSString *splitLine = @"\\n+";
        NSString *splitTimestamp  = @"\\t+";
        NSString *splitBytes = @"\\s+";
        NSArray<NSString *>  *fileArray = nil;
        NSUInteger i = 0;

        fileArray = [scc MP42_componentsSeparatedByRegex:splitLine];

        NSMutableArray *sampleArray = [[NSMutableArray alloc] initWithCapacity:fileArray.count];

        UInt64 dropFrame = 0;
        UInt64 frameDrop = 0;
        UInt64 minutesDrop = 0;

        for (NSString *line in fileArray) {
            NSArray<NSString *> *lineArray = [line MP42_componentsSeparatedByRegex:splitTimestamp];

            if (lineArray.count < 2) {
                continue;
            }

            startTime = ParseTimeCode(lineArray[0].UTF8String, 30000, NO, &dropFrame);

            MP42TextSample *sample = [[MP42TextSample alloc] init];
            sample.timestamp = startTime;
            sample.title = [lineArray lastObject];

            [sampleArray addObject:sample];
        }

        for (MP42TextSample *ccSample in sampleArray) {
            if (self.isCancelled) {
                break;
            }

            NSArray *bytesArray   = nil;
            MP4Duration sampleDuration = 0;
            bytesArray = [ccSample.title MP42_componentsSeparatedByRegex:splitBytes];

            NSUInteger byteCount = bytesArray.count * 2;
            UInt8 *bytes = malloc(sizeof(UInt8) * byteCount * 2 + (sizeof(UInt8) * 8));
            UInt8 *bytesPos = bytes;

            // Write out the size of the atom
            *(SInt32 *)bytesPos = EndianS32_NtoB(8 + byteCount);
            bytesPos += sizeof(SInt32);

            // Write out the atom type
            *(OSType*) bytesPos = EndianU32_NtoB('cdat');
            bytesPos += sizeof(OSType);

            for (NSString *hexByte in bytesArray) {
                ParseByte(hexByte.UTF8String, bytesPos , 1);
                ParseByte(hexByte.UTF8String + 2, bytesPos + 1, 1);
                bytesPos +=2;
            }

            if (firstSample && ccSample.timestamp != 0 && i == 0) {
                MP42TextSample *textSample = sampleArray[1];
                sampleDuration = textSample.timestamp - ccSample.timestamp;
                firstSample = NO;
                UInt8 *emptyBuffer = malloc(sizeof(UInt8) * 8);
                UInt8 empty[8] = {0,0,0,8,'c','d','a','t'};
                memcpy(emptyBuffer, empty, sizeof(UInt8) * 8);

                MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                sample->data = emptyBuffer;
                sample->size = 8;
                sample->duration = ccSample.timestamp *= 1001;
                sample->offset = 0;
                sample->decodeTimestamp = 0;
                sample->flags |= MP42SampleBufferFlagIsSync;
                sample->trackId = trackId;

                [self enqueue:sample];

                frameDrop += ccSample.timestamp;
                minutesDrop += frameDrop;
            }
            else if (i + 1 < sampleArray.count) {
                MP42TextSample *textSample = sampleArray[i + 1];
                sampleDuration = textSample.timestamp - ccSample.timestamp;
                frameDrop += sampleDuration;
                minutesDrop += sampleDuration;

                if (frameDrop >= 1800 && dropFrame) {
                    if (minutesDrop > 18000) {
                        minutesDrop -= 16200;
                    }
                    else {
                        sampleDuration -= 2;
                    }

                    frameDrop -= 1800;
                }
            }
            else {
                sampleDuration = 6;
            }
            
            MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
            sample->data = bytes;
            sample->size = (uint32_t)byteCount + 8;
            sample->duration = sampleDuration * 1001;
            sample->offset = 0;
            sample->decodeTimestamp = 0;
            sample->flags |= MP42SampleBufferFlagIsSync;
            sample->trackId = trackId;
            
            [self enqueue:sample];

            i++;
            self.progress = ((CGFloat)i / sampleArray.count) * 100;
        }
        
        [self setDone];
    }
}

- (NSString *)description
{
    return @"CC demuxer";
}

@end
