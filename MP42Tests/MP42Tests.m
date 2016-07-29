//
//  MP42Tests.m
//  MP42Tests
//
//  Created by Damiano Galassi on 01/11/13.
//  Copyright (c) 2013 Damiano Galassi. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MP42File.h"

@interface MP42Tests : XCTestCase

@property (nonatomic, retain) MP42File *mp4;

@end

@implementation MP42Tests

- (void)setUp
{
    [super setUp];
    self.mp4 = [[[MP42File alloc] init] autorelease];
}

- (void)tearDown
{
    self.mp4 = nil;
    [super tearDown];
}

- (void)testCreation
{
    XCTAssertNotNil(self.mp4, @"MP4File is nil");
}

@end
