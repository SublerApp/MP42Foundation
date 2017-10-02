//
//  MP42SSAConverter.m
//  SSA parser
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2017 Damiano Galassi. All rights reserved.
//

#import "MP42SSAConverter.h"
#import "MP42SSAParser.h"

typedef NS_ENUM(NSUInteger, MP42SSATokenType) {
    MP42SSATokenTypeText,
    MP42SSATokenTypeBoldOpen,
    MP42SSATokenTypeBoldClose,
    MP42SSATokenTypeItalicOpen,
    MP42SSATokenTypeItalicClose,
    MP42SSATokenTypeUnderlinedOpen,
    MP42SSATokenTypeUnderlinedClose,
    MP42SSATokenTypeDrawingOpen,
    MP42SSATokenTypeDrawingClose
};

@interface MP42SSAToken : NSObject
{
@public
    MP42SSATokenType _type;
    NSString *_text;
}
@end

@implementation MP42SSAToken

@end

@interface MP42SSAConverter ()

@property (nonatomic, readonly) MP42SSAParser *parser;

@end

@implementation MP42SSAConverter

- (instancetype)initWithParser:(MP42SSAParser *)parser
{
    self = [super init];
    if (self) {
        _parser = parser;
    }
    return self;
}

- (NSArray<NSString *> *)convertedLines
{
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (MP42SSALine *line in _parser.lines) {
        NSString *convertedLine = [self convertLine:line];
        if (convertedLine.length) {
            [result addObject:convertedLine];
        }
    }
    return result;
}

#pragma mark - Conversion

- (NSString *)convertLine:(MP42SSALine *)line
{
    NSMutableString *result = [NSMutableString string];
    NSArray<MP42SSAToken *> *tokens = tokenizer(line.text);

    BOOL drawingMode = NO;

    for (MP42SSAToken *token in tokens) {
        NSString *textToAppend = nil;

        if (token->_type == MP42SSATokenTypeText) {
            textToAppend = token->_text;
        }
        else if (token->_type == MP42SSATokenTypeBoldOpen) {
            textToAppend = @"<b>";
        }
        else if (token->_type == MP42SSATokenTypeBoldClose) {
            textToAppend = @"</b>";
        }
        else if (token->_type == MP42SSATokenTypeItalicOpen) {
            textToAppend = @"<i>";
        }
        else if (token->_type == MP42SSATokenTypeItalicClose) {
            textToAppend = @"</i>";
        }
        else if (token->_type == MP42SSATokenTypeUnderlinedOpen) {
            textToAppend = @"<u>";
        }
        else if (token->_type == MP42SSATokenTypeUnderlinedClose) {
            textToAppend = @"</u>";
        }
        else if (token->_type == MP42SSATokenTypeDrawingOpen) {
            drawingMode = YES;
        }
        else if (token->_type == MP42SSATokenTypeDrawingClose) {
            drawingMode = NO;
        }

        if (textToAppend && drawingMode == NO) {
            [result appendString:textToAppend];
        }
    }

    [result replaceOccurrencesOfString:@"\\N" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"\\n" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, result.length)];

    if (result.length) {
        if (line.style.bold) {
            [result insertString:@"<b>" atIndex:0];
        }
        if (line.style.underline) {
            [result insertString:@"<u>" atIndex:0];
        }
        if (line.style.italic) {
            [result insertString:@"<i>" atIndex:0];
        }
    }

    return result;
}

static inline NSArray<MP42SSAToken *> *tokenizer(NSString *line)
{
    NSScanner *sc = [NSScanner scannerWithString:line];
    NSMutableArray<MP42SSAToken *> *tokens = [NSMutableArray array];
    NSString *string;

    while ([sc scanUpToString:@"{" intoString:&string] || [sc scanString:@"{" intoString:&string]) {
        if (![string hasPrefix:@"{"]) {
            addToken(string, MP42SSATokenTypeText, tokens);
        }

        [sc scanString:@"{" intoString:nil];

        if ([sc scanUpToString:@"}" intoString:&string] || [sc scanString:@"}" intoString:&string]) {
            NSScanner *tagSc = [NSScanner scannerWithString:string];

            while ([tagSc scanUpToString:@"\\" intoString:&string] || [tagSc scanString:@"\\" intoString:&string]) {
                if (![string hasPrefix:@"\\"]) {
                    [sc scanString:@"\\" intoString:nil];

                    if ([string hasPrefix:@"p"]) {
                        if ([string hasPrefix:@"p0"]) {
                            addToken(string, MP42SSATokenTypeDrawingClose, tokens);
                        }
                        else if (![string hasPrefix:@"pos"]) {
                            addToken(string, MP42SSATokenTypeDrawingOpen, tokens);
                        }
                    }
                }
            }

            [sc scanString:@"}" intoString:nil];
        }
    }

    return tokens;
}

static inline void addToken(NSString *text, MP42SSATokenType type, NSMutableArray<MP42SSAToken *> *tokens)
{
    MP42SSAToken *token = [[MP42SSAToken alloc] init];
    token->_text = text;
    token->_type = type;
    [tokens addObject:token];
}

@end