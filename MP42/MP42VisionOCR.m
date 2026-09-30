//
//  MP42VisionOCR.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/09/2026.
//  Copyright © 2026 Damiano Galassi. All rights reserved.
//

#import "MP42VisionOCR.h"

@import Vision;

@interface MP42VisionOCR ()
@property (nonatomic, readonly) NSString *language;
@property (nonatomic, readonly) dispatch_semaphore_t done;
@end

@implementation MP42VisionOCR

- (nonnull instancetype)initWithLanguage:(nonnull NSString *)language
{
    self = [super init];
    if (self) {
        _language = [language copy];
        _done = dispatch_semaphore_create(0);
    }
    return self;
}

- (nullable NSString *)performOCROnCGImage:(nonnull CGImageRef)image
{
    __block NSMutableString *text = [[NSMutableString alloc] init];

    VNImageRequestHandler *requestHandler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];

    VNRecognizeTextRequest *textRequest = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        NSArray<VNRecognizedTextObservation *> *observations = request.results;
        if (observations.count) {
            for (VNRecognizedTextObservation *currentObservation in request.results) {
                NSArray<VNRecognizedText *> *topCandidate = [currentObservation topCandidates:1];
                VNRecognizedText *recognizedText = topCandidate.firstObject;
                if (recognizedText) {
                    if (text.length) {
                        [text appendString:@"\n"];
                    }
                    [text appendString:recognizedText.string];
                }
            }
        }
        dispatch_semaphore_signal(self->_done);
    }];
    textRequest.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    textRequest.recognitionLanguages = @[_language];
    textRequest.revision = VNRecognizeTextRequestRevision3;
    textRequest.usesLanguageCorrection = YES;

    NSError *error;
    [requestHandler performRequests:@[textRequest] error:&error];

    dispatch_semaphore_wait(_done, DISPATCH_TIME_FOREVER);

    return text;
}

@end
