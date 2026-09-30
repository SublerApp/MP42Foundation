//
//  MP42TextRecognizer.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/09/2026.
//  Copyright © 2026 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MP42TextRecognizer <NSObject>

- (instancetype)initWithLanguage:(NSString *)language;
- (nullable NSString *)performOCROnCGImage:(CGImageRef)image;

@end

NS_ASSUME_NONNULL_END
