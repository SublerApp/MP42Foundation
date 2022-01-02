//
//  MP42SSAParser.h
//  SSA parser
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42Utilities.h"

NS_ASSUME_NONNULL_BEGIN

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SSAStyle : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly, nullable) NSString *fontName;
@property (nonatomic, readonly) int fontSize;
@property (nonatomic, readonly) long primaryColour;
@property (nonatomic, readonly) long secondaryColour;
@property (nonatomic, readonly) long outlineColour;
@property (nonatomic, readonly) long backColour;
@property (nonatomic, readonly) BOOL bold;
@property (nonatomic, readonly) BOOL italic;
@property (nonatomic, readonly) BOOL underline;
@property (nonatomic, readonly) BOOL strikeOut;
@property (nonatomic, readonly) float scaleX;
@property (nonatomic, readonly) float scaleY;
@property (nonatomic, readonly) int spacing;
@property (nonatomic, readonly) float angle;
@property (nonatomic, readonly) short borderStyle;
@property (nonatomic, readonly) short outline;
@property (nonatomic, readonly) short shadow;
@property (nonatomic, readonly) short alignment;
@property (nonatomic, readonly) int marginL;
@property (nonatomic, readonly) int marginR;
@property (nonatomic, readonly) int marginV;
@property (nonatomic, readonly) int alphaLevel;
@property (nonatomic, readonly) int encoding;

@end

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SSALine : NSObject

@property (nonatomic, readonly) int layer;
@property (nonatomic, readonly) unsigned start;
@property (nonatomic, readonly) unsigned end;
@property (nonatomic, readonly, nullable) MP42SSAStyle *style;
@property (nonatomic, readonly, nullable) NSString *name;
@property (nonatomic, readonly) int marginL;
@property (nonatomic, readonly) int marginR;
@property (nonatomic, readonly) int marginV;
@property (nonatomic, readonly, nullable) NSString *effect;
@property (nonatomic, readonly, nullable) NSString *text;

@end

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SSAParser : NSObject

- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithMKVHeader:(NSString *)header;

@property (nonatomic, readonly) NSArray<MP42SSALine *> *lines;
@property (nonatomic, readonly) NSDictionary<NSString *, MP42SSAStyle *> *styles;
@property (nonatomic, readonly) unsigned duration;

- (nullable MP42SSALine *)addLine:(NSString *)line;

@end

NS_ASSUME_NONNULL_END
