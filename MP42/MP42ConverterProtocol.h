//
//  MP42ConverterProtocol.h
//  Subler
//
//  Created by Damiano Galassi on 05/08/13.
//
//

#import <Foundation/Foundation.h>
#import "MP42SampleBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MP42ConverterProtocol <NSObject>

@optional
- (nullable NSData *)magicCookie;

@required
- (void)addSample:(MP42SampleBuffer *)sample;
- (nullable MP42SampleBuffer *)copyEncodedSample;

@end

NS_ASSUME_NONNULL_END
