//
//  MP42SSAParser.h
//  Subler
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2017 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MP42SSALine : NSObject

@property (nonatomic, readwrite) unsigned start;
@property (nonatomic, readwrite) unsigned end;
@property (nonatomic, readwrite) NSString *text;

@end

@interface MP42SSAParser : NSObject

- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithHeader:(NSString *)header;

@property (nonatomic, readonly) NSArray<MP42SSALine *> *lines;

- (void)addLine:(NSString *)line;

@end

