//
//  MP42Sample.m
//  Subler
//
//  Created by Damiano Galassi on 29/06/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import "MP42SampleBuffer.h"

@implementation MP42SampleBuffer

- (void)dealloc {
    free(data);
    if (attachments) {
        CFRelease(attachments);
    }
}

@end
