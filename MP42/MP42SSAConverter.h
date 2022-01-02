//
//  MP42SSAConverter.h
//  SSA parser
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42Utilities.h"

NS_ASSUME_NONNULL_BEGIN

@class MP42SSAParser;
@class MP42SSALine;

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SSAConverter : NSObject

- (instancetype)initWithParser:(MP42SSAParser *)parser;
- (NSString *)convertLine:(MP42SSALine *)line;

@end

NS_ASSUME_NONNULL_END
