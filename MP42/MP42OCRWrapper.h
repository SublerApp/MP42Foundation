//
//  SBOcr.h
//  Subler
//
//  Created by Damiano Galassi on 27/03/11.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42Utilities.h"

NS_ASSUME_NONNULL_BEGIN

MP42_OBJC_DIRECT_MEMBERS
@interface MP42OCRWrapper : NSObject

- (instancetype)initWithLanguage:(NSString *)language;
- (nullable NSString *)performOCROnCGImage:(CGImageRef)image;

@end

NS_ASSUME_NONNULL_END
