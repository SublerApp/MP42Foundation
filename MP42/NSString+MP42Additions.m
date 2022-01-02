//
//  NSString+MP42Additions.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 18/09/15.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "NSString+MP42Additions.h"

@implementation NSString (MP42Additions)

- (NSArray<NSString *> *)MP42_componentsSeparatedByRegex:(NSString *)regex {

    NSParameterAssert(regex);

    NSMutableArray<NSString *> *results = [NSMutableArray array];
    __block NSRange start = NSMakeRange(0, 0);

    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:regex
                                                                       options:NSRegularExpressionCaseInsensitive
                                                                         error:nil];

    [r enumerateMatchesInString:self options:0 range:NSMakeRange(0, self.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSRange end = match.range;
        NSRange componentRange = NSMakeRange(start.location, end.location - start.location);
        NSString *component = [self substringWithRange:componentRange];
        if (component.length) {
            [results addObject:component];
        }
        start = NSMakeRange(end.location + end.length, 0);
    }];

    if (start.location < self.length) {
        NSRange componentRange = NSMakeRange(start.location, self.length - start.location);
        NSString *component = [self substringWithRange:componentRange];
        if (component.length) {
            [results addObject:component];
        }
    }

    return results;
}

- (BOOL)MP42_isMatchedByRegex:(NSString *)regex {

    NSParameterAssert(regex);

    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:regex
                                                                       options:NSRegularExpressionCaseInsensitive
                                                                         error:nil];

    return ([r matchesInString:self options:0 range:NSMakeRange(0, self.length)].count) > 0;
}

- (NSString *)MP42_stringByMatching:(NSString *)regex capture:(NSInteger)capture {
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:regex options:0 error:NULL];
    NSTextCheckingResult *match = [r firstMatchInString:self options:0 range:NSMakeRange(0, self.length)];
    return [self substringWithRange:[match rangeAtIndex:capture]];
}

@end
