//
//  SBOcr.mm
//  Subler
//
//  Created by Damiano Galassi on 27/03/11.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42OCRWrapper.h"
#import "MP42Languages.h"

// Tesseract OCR
#include <tesseract/baseapi.h>

using namespace tesseract;

class OCRWrapper {
public:
    OCRWrapper(NSString *lang, NSURL *base_path, OcrEngineMode mode) {
        @autoreleasepool {
            const char *path = nil;
            if (base_path) {
                path = base_path.fileSystemRepresentation;
            } else {
                path = [[NSBundle bundleForClass:[MP42OCRWrapper class]].bundlePath stringByAppendingString:@"/Versions/A/Resources/tessdata/"].fileSystemRepresentation;
            }

            int result = tess_base_api.Init(path, lang.UTF8String, mode);
            if (result == -1) {
                throw EIO;
            }
        }
    }

    char * OCRFrame(const unsigned char *image, size_t bytes_per_pixel, size_t bytes_per_line, size_t width, size_t height) {
        tess_base_api.SetImage(image, (int)width, (int)height, (int)bytes_per_pixel, (int)bytes_per_line);
        tess_base_api.SetSourceResolution(70);
        tess_base_api.SetRectangle(0, 0, (int)width, (int)height);
        char *text = tess_base_api.GetUTF8Text();
        return text;
    }

    void End() {
        tess_base_api.End();
    }

protected:
    TessBaseAPI tess_base_api;
};

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42OCRWrapper {
    OCRWrapper *tess_base;
}

- (NSURL *)appSupporTessdatatUrl
{
    NSURL *URL = nil;

    NSArray *allPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                            NSUserDomainMask,
                                                            YES);
    if (allPaths.count) {
        NSString *path = [[allPaths lastObject] stringByAppendingPathComponent:@"Subler"];
        URL = [NSURL fileURLWithPath:path isDirectory:YES];

        if (URL) {
            return [[URL URLByAppendingPathComponent:@"tessdata" isDirectory:YES] URLByAppendingPathComponent:@"v4" isDirectory:YES];
        }
    }

    return nil;
}

- (BOOL)tessdataAvailableForLanguage:(NSString *)language
{
    NSURL *URL = [self appSupporTessdatatUrl];

    if (URL) {
        NSString *fileName =  [NSString stringWithFormat:@"%@.traineddata", language];
        URL =  [URL URLByAppendingPathComponent:fileName];

        if ([NSFileManager.defaultManager fileExistsAtPath:URL.path]) {
            return YES;
        }
    }

    return NO;
}

- (instancetype)initWithLanguage:(NSString *)language
{
    if ((self = [super init])) {
        NSString *lang = language;

        // ISO_639_2 language code required?
        if ([language isEqualToString:@"zh-Hans"]) {
            lang = @"chi_sim";
        }
        else if ([language isEqualToString:@"zh-Hant"]) {
            lang = @"chi_tra";
        }
        else {
            lang = [MP42Languages.defaultManager ISO_639_2CodeForExtendedTag:language];
        }

        NSURL *dataURL = [self appSupporTessdatatUrl];
        OcrEngineMode mode = OEM_TESSERACT_ONLY;
        if (![self tessdataAvailableForLanguage:lang]) {
            lang = @"eng";
            mode = OEM_LSTM_ONLY;
            dataURL = nil;
        }

        try {
            tess_base = new OCRWrapper(lang, dataURL, mode);
        }
        catch(int e) {
            tess_base = new OCRWrapper(@"eng", nil, OEM_LSTM_ONLY);
        }
    }
    return self;
}

- (NSString *)performOCROnCGImage:(CGImageRef)cgImage {
    NSMutableString *text = nil;

    OCRWrapper *ocr = tess_base;
    size_t bytes_per_line   = CGImageGetBytesPerRow(cgImage);
    size_t bytes_per_pixel  = CGImageGetBitsPerPixel(cgImage) / 8.0;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
    const UInt8 *imageData = CFDataGetBytePtr(data);

    char *string = ocr->OCRFrame(imageData,
                                 bytes_per_pixel,
                                 bytes_per_line,
                                 width,
                                 height);
    CFRelease(data);

    if (string && strlen(string)) {
        text = [NSMutableString stringWithUTF8String:string];
        if (text && [text characterAtIndex:[text length] -1] == '\n') {
            [text replaceOccurrencesOfString:@"\n\n" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, text.length)];
        }
    }

    delete[] string;

    return text;
}

- (void)dealloc {
    OCRWrapper *ocr = tess_base;
    ocr->End();
    delete ocr;
}

@end
