//
//  MP42VobSubImporter.m
//  Subler
//
//  Created by Damiano Galassi on 20/12/12.
//  Based on parts of Perian's source code.
//

#import "MP42VobSubImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42SubUtilities.h"
#import "MP42Languages.h"
#import "MP42File.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Private.h"
#import "MP42SampleBuffer.h"

MP42_OBJC_DIRECT_MEMBERS
@interface SBVobSubSample : NSObject
{
@public
	long		timeStamp;
	long		fileOffset;
}

- (id)initWithTime:(long)time offset:(long)offset;
@end

MP42_OBJC_DIRECT_MEMBERS
@interface SBVobSubTrack : NSObject
{
@public
	NSArray         *privateData;
	NSString		*language;
	int				index;
    long            duration;
	NSMutableArray<SBVobSubSample *> *samples;
}

- (id)initWithPrivateData:(NSArray *)idxPrivateData language:(NSString *)lang andIndex:(int)trackIndex;
- (void)addSample:(SBVobSubSample *)sample;
- (void)addSampleTime:(long)time offset:(long)offset;

@end

MP42_OBJC_DIRECT_MEMBERS
@implementation SBVobSubSample

- (id)initWithTime:(long)time offset:(long)offset
{
	self = [super init];
	if(!self)
		return self;

	timeStamp = time;
	fileOffset = offset;

	return self;
}

@end

MP42_OBJC_DIRECT_MEMBERS
@implementation SBVobSubTrack

- (id)initWithPrivateData:(NSArray *)idxPrivateData language:(NSString *)lang andIndex:(int)trackIndex
{
	self = [super init];
	if(!self)
		return self;

	privateData = [idxPrivateData copy];
	language = [lang copy];
	index = trackIndex;
	samples = [[NSMutableArray alloc] init];

	return self;
}

- (void)addSample:(SBVobSubSample *)sample
{
	[samples addObject:sample];
    duration = sample->timeStamp;
}

- (void)addSampleTime:(long)time offset:(long)offset
{
	SBVobSubSample *sample = [[SBVobSubSample alloc] initWithTime:time offset:offset];
	[self addSample:sample];
}

@end

typedef enum {
	VOB_SUB_STATE_READING_PRIVATE,
	VOB_SUB_STATE_READING_TRACK_HEADER,
	VOB_SUB_STATE_READING_DELAY,
	VOB_SUB_STATE_READING_TRACK_DATA
} VobSubState;

static NSString *getNextVobSubLine(NSEnumerator *lineEnum)
{
	NSString *line;
	while ((line = [lineEnum nextObject]) != nil) {
		//Reject empty lines which may contain whitespace
		if([line length] < 3)
			continue;
		
		if([line characterAtIndex:0] == '#')
			continue;
		
		break;
	}
	return line;
}

static NSArray<SBVobSubTrack *> * LoadVobSubSubtitles(NSURL *theDirectory, NSString *filename)
{
    @autoreleasepool {
        NSURL *nsURL = [theDirectory URLByAppendingPathComponent:filename];
        NSString *idxContent = STLoadFileWithUnknownEncoding(nsURL);
        NSData *privateData = nil;

        VobSubState state = VOB_SUB_STATE_READING_PRIVATE;
        SBVobSubTrack *currentTrack = nil;
        int imageWidth = 0, imageHeight = 0;
        long delay=0;

        NSURL *subFileURL = [[nsURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"sub"];

        if ([idxContent length]) {
            NSError *nsErr;
            NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:subFileURL.path error:&nsErr];
            if (!attr) goto bail;
            int subFileSize = [[attr objectForKey:NSFileSize] intValue];

            NSArray *lines = [idxContent componentsSeparatedByString:@"\n"];
            NSMutableArray *privateLines = [NSMutableArray array];
            NSEnumerator *lineEnum = [lines objectEnumerator];
            NSString *line;

            NSMutableArray<SBVobSubTrack *> *tracks = [NSMutableArray array];

            while((line = getNextVobSubLine(lineEnum)) != NULL)
            {
                if([line hasPrefix:@"timestamp: "])
                    state = VOB_SUB_STATE_READING_TRACK_DATA;
                else if([line hasPrefix:@"id: "])
                {
                    if(privateData == nil)
                    {
                        NSString *allLines = [privateLines componentsJoinedByString:@"\n"];
                        privateData = [allLines dataUsingEncoding:NSUTF8StringEncoding];
                    }
                    state = VOB_SUB_STATE_READING_TRACK_HEADER;
                }
                else if([line hasPrefix:@"delay: "])
                    state = VOB_SUB_STATE_READING_DELAY;
                else if(state != VOB_SUB_STATE_READING_PRIVATE)
                    state = VOB_SUB_STATE_READING_TRACK_HEADER;

                switch(state)
                {
                    case VOB_SUB_STATE_READING_PRIVATE:
                        [privateLines addObject:line];
                        if([line hasPrefix:@"size: "])
                        {
                            sscanf([line UTF8String], "size: %dx%d", &imageWidth, &imageHeight);
                        }
                        break;
                    case VOB_SUB_STATE_READING_TRACK_HEADER:
                        if([line hasPrefix:@"id: "])
                        {
                            char *langStr = (char *)malloc(line.length * sizeof(char));
                            int index;
                            sscanf([line UTF8String], "id: %s index: %d", langStr, &index);
                            size_t langLength = strlen(langStr);
                            if(langLength > 0 && langStr[langLength-1] == ',')
                                langStr[langLength-1] = 0;
                            NSString *language = [NSString stringWithUTF8String:langStr];
                            free(langStr);

                            currentTrack = [[SBVobSubTrack alloc] initWithPrivateData:privateLines language:language andIndex:index];
                            [tracks addObject:currentTrack];
                        }
                        break;
                    case VOB_SUB_STATE_READING_DELAY:
                        delay = ParseSubTime([[line substringFromIndex:7] UTF8String], 1000, YES);
                        break;
                    case VOB_SUB_STATE_READING_TRACK_DATA:
                    {
                        char *timeStr = (char *)malloc(line.length * sizeof(char));
                        unsigned int position;
                        sscanf(line.UTF8String, "timestamp: %s filepos: %x", timeStr, &position);
                        long time = ParseSubTime(timeStr, 1000, YES);
                        free(timeStr);
                        if (position > subFileSize) {
                            position = subFileSize;
                        }
                        [currentTrack addSampleTime:time + delay offset:position];
                    }
                        break;
                }
            }

            return [tracks copy];
        }
    bail:
        NSLog(@"Exception occurred while importing VobSub");
        return nil;
    }
}

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42VobSubImporter {
@private
    NSArray *_VobSubTracks;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"idx"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError * __autoreleasing *)outError
{
    if ((self = [super initWithURL:fileURL])) {

        MP42TrackId count = 0;
        _VobSubTracks = LoadVobSubSubtitles(self.fileURL.URLByDeletingLastPathComponent, self.fileURL.lastPathComponent);

        for (SBVobSubTrack *track in _VobSubTracks) {
            MP42SubtitleTrack *newTrack = [[MP42SubtitleTrack alloc] init];

            newTrack.format = kMP42SubtitleCodecType_VobSub;
            newTrack.URL = self.fileURL;
            newTrack.alternateGroup = 2;
            newTrack.trackId = count++;
            newTrack.language = [MP42Languages.defaultManager extendedTagForISO_639_1:track->language];
            newTrack.timescale = 1000;
            newTrack.duration = track->duration;

            [self addTrack:newTrack];
        }

        if (!self.tracks.count) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be opened.", @"vobsub error message"),
                                      MP42LocalizedString(@"The file is not a idx file, or it does not contain any subtitles.", @"vobsub error message"), 100);
            }
            return nil;
        }
    }

    return self;
}

- (NSData *)magicCookieForTrack:(MP42Track *)track
{
    SBVobSubTrack *vobTrack = [_VobSubTracks objectAtIndex:track.sourceId];
    NSData *magicCookie = nil;

    for (NSString *line in vobTrack->privateData) {
        if ([line hasPrefix:@"palette: "]) {
            const char *palette = [line UTF8String];
            UInt32 colorPalette[32];

            if (palette != NULL) {
                sscanf(palette, "palette: %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx, %lx",
                       (unsigned long*)&colorPalette[ 0], (unsigned long*)&colorPalette[ 1], (unsigned long*)&colorPalette[ 2], (unsigned long*)&colorPalette[ 3],
                       (unsigned long*)&colorPalette[ 4], (unsigned long*)&colorPalette[ 5], (unsigned long*)&colorPalette[ 6], (unsigned long*)&colorPalette[ 7],
                       (unsigned long*)&colorPalette[ 8], (unsigned long*)&colorPalette[ 9], (unsigned long*)&colorPalette[10], (unsigned long*)&colorPalette[11],
                       (unsigned long*)&colorPalette[12], (unsigned long*)&colorPalette[13], (unsigned long*)&colorPalette[14], (unsigned long*)&colorPalette[15]);
            }
            magicCookie = [NSData dataWithBytes:colorPalette length:sizeof(UInt32)*16];
        }
    }

    return magicCookie;
}

- (void)demux
{
    @autoreleasepool {

        NSURL *subFileURL = [self.fileURL.URLByDeletingPathExtension URLByAppendingPathExtension:@"sub"];

        NSData *subFileData = [NSData dataWithContentsOfURL:subFileURL];

        NSInteger tracksNumber = self.inputTracks.count;
        NSInteger tracksDone = 0;

        for (MP42Track *track in self.inputTracks) {
            SBVobSubTrack *vobTrack = [_VobSubTracks objectAtIndex:track.sourceId];
            SBVobSubSample *firstSample = nil;

            uint64_t lastTime = 0;
            NSUInteger sampleCount = vobTrack->samples.count;

            for (NSUInteger i = 0; i < sampleCount && !self.isCancelled; i++) {
                SBVobSubSample *currentSample = [vobTrack->samples objectAtIndex:i];
                long offset = currentSample->fileOffset;
                long nextOffset;
                if (i == sampleCount - 1) {
                    nextOffset = subFileData.length;
                } else {
                    nextOffset = [vobTrack->samples objectAtIndex:i+1]->fileOffset;
                }
                int size = (int)(nextOffset - offset);
                if (size < 0) {
                    //Skip samples for which we cannot determine size
                    continue;
                }

                NSData *subData = [subFileData subdataWithRange:NSMakeRange(offset, size)];
                uint8_t *extracted = (uint8_t *)malloc(size);
                //The index here likely should really be track->index, but I'm not sure we can really trust it.
                int extractedSize = ExtractVobSubPacket(extracted, (UInt8 *)subData.bytes, size, &size, -1);

                uint16_t startTimestamp, endTimestamp;
                uint8_t forced;
                if (!ReadPacketTimes(extracted, extractedSize, &startTimestamp, &endTimestamp, &forced)) {
                    free(extracted);
                    continue;
                }

                uint64_t startTime = currentSample->timeStamp + startTimestamp;
                uint64_t endTime = currentSample->timeStamp + endTimestamp;

                uint64_t duration = endTimestamp - startTimestamp;
                if (duration <= 0 && i < sampleCount - 1) {
                    //Sample with no end duration, use the duration of the next one
                    endTime = [vobTrack->samples objectAtIndex:i+1]->timeStamp;
                    duration = endTime - startTime;
                }
                if (duration <= 0) {
                    //Skip samples which are broken
                    free(extracted);
                    continue;
                }
                if (firstSample == nil) {
                    currentSample->timeStamp = startTime;
                    firstSample = currentSample;
                }
                if (lastTime != startTime) {
                    //insert a sample with no real data, to clear the subs
                    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                    sample->size = 2;
                    sample->data = calloc(1, 2);
                    sample->timescale = 1000;
                    sample->duration = startTime - lastTime;
                    sample->offset = 0;
                    sample->presentationTimestamp = startTime;
                    sample->presentationOutputTimestamp = startTime;
                    sample->decodeTimestamp = startTime;
                    sample->flags |= MP42SampleBufferFlagIsSync;
                    sample->trackId = track.sourceId;

                    [self enqueue:sample];
                }

                MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
                sample->data = extracted;
                sample->size = size;
                sample->duration = duration;
                sample->offset = 0;
                sample->presentationTimestamp = startTime;
                sample->presentationOutputTimestamp = startTime;
                sample->decodeTimestamp = startTime;
                sample->flags |= MP42SampleBufferFlagIsSync;
                sample->trackId = track.sourceId;
                
                [self enqueue:sample];

                lastTime = endTime;
                
                self.progress = ((i / (CGFloat) sampleCount ) * 100 / tracksNumber) + (tracksDone / (CGFloat) tracksNumber * 100);
            }
            tracksDone++;
        }
        
        [self setDone];
    }
}

- (NSString *)description
{
    return @"VobSub demuxer";
}

@end
