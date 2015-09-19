//
//  MP42ComponentLoader.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 24/07/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import "MP42ComponentLoader.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>

#include <dlfcn.h>

#include <TargetConditionals.h>
#if TARGET_RT_BIG_ENDIAN
#   define FourCC2Str(fourcc) (const char[]){*((char*)&fourcc), *(((char*)&fourcc)+1), *(((char*)&fourcc)+2), *(((char*)&fourcc)+3),0}
#else
#   define FourCC2Str(fourcc) (const char[]){*(((char*)&fourcc)+3), *(((char*)&fourcc)+2), *(((char*)&fourcc)+1), *(((char*)&fourcc)+0),0}
#endif

static NSMutableDictionary *_loadedComponents;

@implementation MP42ComponentLoader

+ (MP42ComponentLoader *)sharedLoader {
    static dispatch_once_t pred;
    static MP42ComponentLoader *sharedManager = nil;

    dispatch_once(&pred, ^{ sharedManager = [[self alloc] init]; });
    return sharedManager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _loadedComponents = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)loadBundledComponents {
    @synchronized(self) {
        NSURL *url = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"Decoders"];

        if (![[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:NULL]) {
            return;
        }

        if (![self componentLoadedForFormat:kAudioFormatAC3]) {
            OSStatus err = [self loadComponent:kAudioDecoderComponentType
                                        format:kAudioFormatAC3
                                  manufacturer:'cd3r'
                                           url:[url URLByAppendingPathComponent:@"A52Codec.component/Contents/MacOS/A52Codec"]
                                         entry:"ACShepA52DecoderEntry"];
            if (err) {
                NSLog(@"AC-3 Decoder not loaded");
            }
        }

        if (![self componentLoadedForFormat:'XiVs']) {
            OSStatus err = [self loadComponent:kAudioDecoderComponentType
                                        format:'XiVs'
                                  manufacturer:'Xiph'
                                           url:[url URLByAppendingPathComponent:@"Perian.component/Contents/MacOS/Perian"]
                                         entry:"FFissionVBRDecoderEntry"];
            if (err) {
                NSLog(@"Vorbis Decoder not loaded");
            }
        }

        if (![self componentLoadedForFormat:'XiFL']) {
            OSStatus err = [self loadComponent:kAudioDecoderComponentType
                                        format:'XiFL'
                                  manufacturer:'Xiph'
                                           url:[url URLByAppendingPathComponent:@"XiphQT (decoders).component/Contents/MacOS/XiphQT (decoders)"]
                                         entry:"CAFLACDecoderEntry"];
            if (err) {
                NSLog(@"FLAC Decoder not loaded");
            }
        }

        if (![self componentLoadedForFormat:'DTS ']) {
            OSStatus err = [self loadComponent:kAudioDecoderComponentType
                                        format:'DTS '
                                  manufacturer:'Peri'
                                           url:[url URLByAppendingPathComponent:@"Perian.component/Contents/MacOS/Perian"]
                                         entry:"FFissionVBRDecoderEntry"];
            if (err) {
                NSLog(@"DTS Decoder not loaded");
            }
        }
    }
}

- (BOOL)componentLoadedForFormat:(OSType)format {
    BOOL loaded = NO;

    if (_loadedComponents[@(FourCC2Str(format))]) {
        loaded = YES;
    } else {
        AudioComponentDescription acd = { 0 };
        acd.componentType = kAudioDecoderComponentType;
        acd.componentSubType = format;
        AudioComponent comp = NULL;

        while((comp = AudioComponentFindNext(comp, &acd))) {
            AudioComponentDescription outDesc = { 0 };
            AudioComponentGetDescription(comp, &outDesc);
            if (outDesc.componentSubType == format) {
                loaded = YES;
            }
        }
    }

    return loaded;
}

- (void)loadedComponents {
    AudioComponentDescription acd = { 0 };
    AudioComponent comp = NULL;
    while((comp = AudioComponentFindNext(comp, &acd))) {
        AudioComponentDescription outDesc = { 0 };
        AudioComponentGetDescription(comp, &outDesc);
        if (outDesc.componentType == kAudioDecoderComponentType) {
            NSLog(@"%s -> %s", FourCC2Str(outDesc.componentManufacturer), FourCC2Str(outDesc.componentSubType));
        }
    }
}

- (OSStatus)loadComponent:(OSType)type
                   format:(OSType)format
             manufacturer:(OSType)manufactorer
                      url:(NSURL *)url
                    entry:(const char *)entry
{
    OSType err = 1;

    if (_loadedComponents[@(FourCC2Str(format))]) {
        return noErr;
    }

    ComponentDescription cd;
    cd.componentType         = type;
    cd.componentSubType      = format;
    cd.componentManufacturer = manufactorer;
    cd.componentFlags        = 0;
    cd.componentFlagsMask    = 0;
    ComponentResult (*ComponentRoutine) (ComponentParameters *cp, Handle componentStorage);
    void *handle = dlopen([[url path] UTF8String], RTLD_LAZY|RTLD_LOCAL);
    if (handle)
    {
        ComponentRoutine = dlsym(handle, entry);
        if (ComponentRoutine)
        {
            if (RegisterComponent(&cd, ComponentRoutine, 0, NULL, NULL, NULL)) {
                err = noErr;
                [_loadedComponents setValue:@YES forKey:@(FourCC2Str(format))];
            }
        }
    }

    return err;
}

- (OSStatus)loadAudioComponent:(OSType)type
                        format:(OSType)format
                  manufacturer:(OSType)manufactorer
                           url:(NSURL *)url
                         entry:(const char *)entry
{
    OSType err = 1;

    if (_loadedComponents[@(FourCC2Str(format))]) {
        return noErr;
    }

    //	fill out the version number for the AU
    UInt32 theVersion = 0x00010000;

    //	fill out the AudioComponentDescription
    AudioComponentDescription theDescription;
    theDescription.componentType = type;
    theDescription.componentSubType = format;
    theDescription.componentManufacturer = manufactorer;
    theDescription.componentFlagsMask = 0;

    AudioComponentPlugInInterface * (*AudioComponentFactoryFunction)(const AudioComponentDescription *inDesc);
    void *handle = dlopen([[url path] UTF8String], RTLD_LAZY|RTLD_LOCAL);
    if (handle)
    {
        AudioComponentFactoryFunction = dlsym(handle, entry);
        if (AudioComponentFactoryFunction)
        {
            if (AudioComponentRegister(&theDescription, CFSTR("My Decoder"),
                                       theVersion, AudioComponentFactoryFunction))
            {
                err = noErr;
                [_loadedComponents setValue:@YES forKey:@(FourCC2Str(format))];
            }
        }
    }


    return err;
}

@end
