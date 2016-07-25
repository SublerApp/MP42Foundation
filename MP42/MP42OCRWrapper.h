//
//  SBOcr.h
//  Subler
//
//  Created by Damiano Galassi on 27/03/11.
//  Copyright 2011 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MP42OCRWrapper : NSObject

- (instancetype)initWithLanguage:(NSString *)language extendedLanguageTag:(NSString *)extendedLanguageTag;
- (NSString *)performOCROnCGImage:(CGImageRef)image;

@end
