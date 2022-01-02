//
//  MP42SSAConverter.m
//  SSA parser
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
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
    NSUInteger textLength = 0;

    BOOL drawingMode = NO;
    BOOL bold = NO;
    BOOL italic = NO;
    BOOL underlined = NO;
    
    if (line.style.bold) {
        [result insertString:@"<b>" atIndex:0];
        bold = YES;
    }
    if (line.style.underline) {
        [result insertString:@"<u>" atIndex:0];
        underlined = YES;
    }
    if (line.style.italic) {
        [result insertString:@"<i>" atIndex:0];
        italic = YES;
    }

    for (MP42SSAToken *token in tokens) {
        NSString *textToAppend = nil;

        if (token->_type == MP42SSATokenTypeText) {
            textToAppend = token->_text;
        }
        else if (token->_type == MP42SSATokenTypeBoldOpen && bold == NO) {
            textToAppend = @"<b>";
            bold = YES;
        }
        else if (token->_type == MP42SSATokenTypeBoldClose && bold == YES) {
            textToAppend = @"</b>";
            bold = NO;
        }
        else if (token->_type == MP42SSATokenTypeItalicOpen && italic == NO) {
            textToAppend = @"<i>";
            italic = YES;
        }
        else if (token->_type == MP42SSATokenTypeItalicClose && italic == YES) {
            textToAppend = @"</i>";
            italic = NO;
        }
        else if (token->_type == MP42SSATokenTypeUnderlinedOpen && underlined == NO) {
            textToAppend = @"<u>";
            underlined = YES;
        }
        else if (token->_type == MP42SSATokenTypeUnderlinedClose && underlined == YES) {
            textToAppend = @"</u>";
            underlined = NO;
        }
        else if (token->_type == MP42SSATokenTypeDrawingOpen) {
            drawingMode = YES;
        }
        else if (token->_type == MP42SSATokenTypeDrawingClose) {
            drawingMode = NO;
        }

        if (textToAppend && drawingMode == NO) {
            [result appendString:textToAppend];
            if (token->_type == MP42SSATokenTypeText) {
                textLength += textToAppend.length;
            }
        }
    }
    
    if (bold) {
        [result appendString:@"</b>"];
    }
    if (underlined) {
        [result appendString:@"</u>"];
    }
    if (italic) {
        [result appendString:@"</i>"];
    }

    [result replaceOccurrencesOfString:@"\\N" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"\\n" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, result.length)];

    return textLength ? result : @"";
}

static inline NSArray<MP42SSAToken *> *tokenizer(NSString *line)
{
    NSScanner *sc = [NSScanner scannerWithString:line];
    [sc setCharactersToBeSkipped:nil];

    NSMutableArray<MP42SSAToken *> *tokens = [NSMutableArray array];
    NSString *string;

    while ([sc scanUpToString:@"{" intoString:&string] || [sc scanString:@"{" intoString:&string]) {
        if (![string hasPrefix:@"{"]) {
            addToken(string, MP42SSATokenTypeText, tokens);
        }

        [sc scanString:@"{" intoString:nil];

        if ([sc scanUpToString:@"}" intoString:&string] || [sc scanString:@"}" intoString:&string]) {
            NSScanner *tagSc = [NSScanner scannerWithString:string];
            [sc setCharactersToBeSkipped:nil];

            while ([tagSc scanUpToString:@"\\" intoString:&string] || [tagSc scanString:@"\\" intoString:&string]) {
                if (![string hasPrefix:@"\\"]) {
                    [sc scanString:@"\\" intoString:nil];

                    if (string.length > 1) {
                        unichar tag = [string characterAtIndex:0];
                        unichar tagState = [string characterAtIndex:1];

                        if (tagState >= '0' && tagState <= '9')
                        {
                            if (tagState == '0') {
                                if (tag == 'i') { addToken(string, MP42SSATokenTypeItalicClose, tokens); }
                                else if (tag == 'b') { addToken(string, MP42SSATokenTypeBoldClose, tokens); }
                                else if (tag == 'u') { addToken(string, MP42SSATokenTypeUnderlinedClose, tokens); }
                                else if (tag == 'p') { addToken(string, MP42SSATokenTypeDrawingClose, tokens); }
                            }
                            else {
                                if (tag == 'i') { addToken(string, MP42SSATokenTypeItalicOpen, tokens); }
                                else if (tag == 'b') { addToken(string, MP42SSATokenTypeBoldOpen, tokens); }
                                else if (tag == 'u') { addToken(string, MP42SSATokenTypeUnderlinedOpen, tokens); }
                                else if (tag == 'p') { addToken(string, MP42SSATokenTypeDrawingOpen, tokens); }
                            }
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
