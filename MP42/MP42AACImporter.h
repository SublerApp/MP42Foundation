//
//  MP42AACFileImporter.h
//  Subler
//
//  Created by Damiano Galassi on 07/12/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42FileImporter.h"

@interface MP42AACImporter : MP42FileImporter {
@private
    FILE *inFile;
    int64_t size;

    NSMutableData *aacInfo;
    u_int32_t samplesPerSecond;
}

@end
