//
//  SubUtilities.h
//  Subler
//
//  Created by Alexander Strange on 7/24/07.
//  Copyright 2007 Perian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42TextSample.h"
#import "MP42Utilities.h"
#import "mp4v2.h"

NS_ASSUME_NONNULL_BEGIN

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SubLine : NSObject
{
@public
	NSString *line;
    uint64_t begin_time, end_time;
    uint64_t no; // line number, used only by SBSubSerializer
    unsigned top;
    unsigned forced;
}
- (instancetype)initWithLine:(NSString *)l start:(uint64_t)s end:(uint64_t)e;
- (instancetype)initWithLine:(NSString *)l start:(uint64_t)s end:(uint64_t)e top_pos:(unsigned)p forced:(unsigned)f;
@end

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SubSerializer : NSObject

- (void)addLine:(MP42SubLine *)sline;

@property (nonatomic) BOOL finished;

- (nullable MP42SubLine *)getSerializedPacket;

@property (nonatomic, readonly) BOOL isEmpty;

@property (nonatomic) BOOL positionInformation;
@property (nonatomic) BOOL forced;
@property (nonatomic) BOOL ssa;

@end

NSMutableString *STStandardizeStringNewlines(NSString *str);
extern NSString *STLoadFileWithUnknownEncoding(NSURL *url);
int LoadSRTFromURL(NSURL *url, MP42SubSerializer *ss, MP4Duration *duration);
int LoadSMIFromURL(NSURL *url, MP42SubSerializer *ss, int subCount);

int LoadChaptersFromURL(NSURL *url, NSMutableArray *ss);

unsigned ParseSubTime(const char *time, unsigned secondScale, BOOL hasSign);

@class MP42SampleBuffer;

MP42SampleBuffer * copySubtitleSample(MP4TrackId subtitleTrackId, NSString *string, MP4Duration duration, BOOL forced, BOOL verticalPlacement, BOOL styles, CGSize trackSize, int top) NS_RETURNS_RETAINED;
MP42SampleBuffer * copyEmptySubtitleSample(MP4TrackId subtitleTrackId, MP4Duration duration, BOOL forced) NS_RETURNS_RETAINED;

typedef struct {
	// color format is 32-bit ARGB
	UInt32  pixelColor[16];
	UInt32  duration;
} PacketControlData;

int ExtractVobSubPacket(UInt8 *dest, UInt8 *framedSrc, long srcSize, int * _Nullable usedSrcBytes, int index);
ComponentResult ReadPacketControls(UInt8 *packet, UInt32 palette[_Nonnull 16], PacketControlData *controlDataOut, BOOL *forced);
Boolean ReadPacketTimes(uint8_t *packet, uint32_t length, uint16_t *startTime, uint16_t *endTime, uint8_t *forced);

NS_ASSUME_NONNULL_END

