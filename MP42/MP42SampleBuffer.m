//
//  MP42Sample.m
//  Subler
//
//  Created by Damiano Galassi on 29/06/10.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42SampleBuffer.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42SampleBuffer

- (void)dealloc {
    free(data);
    if (attachments) {
        CFRelease(attachments);
    }
}

@end
