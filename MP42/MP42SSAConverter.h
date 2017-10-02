//
//  MP42SSAConverter.h
//  SSA parser
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2017 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MP42SSAParser;
@class MP42SSALine;

@interface MP42SSAConverter : NSObject

- (instancetype)initWithParser:(MP42SSAParser *)parser;
- (NSString *)convertLine:(MP42SSALine *)line;

@end
