//
//  PSPDFVideoAnnotationView.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKitGlobal.h"
#import "PSPDFVideoAnnotationView.h"
#import "PSPDFAnnotation.h"

@implementation PSPDFVideoAnnotationView
@synthesize annotation = annotation_;
@synthesize URL = URL_;
@synthesize player = player_;
@synthesize autostartEnabled = autostartEnabled_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (void)addPlayerController {
    [player_.view removeFromSuperview];
    player_ = [[MPMoviePlayerController alloc] initWithContentURL:URL_];
    player_.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    player_.view.frame = self.bounds;
    [self addSubview:player_.view]; 
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        PSPDFRegisterObject(self);
        autostartEnabled_ = NO;
        
#if defined(__i386__) || defined(__x86_64__)
        NSLog(@"------------------------------------------------------------------------------");
        NSLog(@"Note: If the embedded video crashes, it's a bug in Apple's Simulator. Please try on a real device.");
        NSLog(@"Referencing \"Error loading /System/Library/Extensions/AudioIPCDriver.kext/... Symbol not found: ___CFObjCIsCollectable.\"");
        NSLog(@"This is a known bug in Xcode 4.1+ / Lion");
        NSLog(@"This note will only show up in the i386 codebase and not on the device.");
        NSLog(@"------------------------------------------------------------------------------");
#endif
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    [player_ stop];
    player_.contentURL = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)layoutSubviews {
    [super layoutSubviews];
    player_.view.frame = self.bounds;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setURL:(NSURL *)URL {
    if (URL != URL_) {
        URL_ = URL;
        //[self addPlayerController];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFAnnotationView

/// page is displayed
- (void)didShowPage:(NSUInteger)page {
    [self addPlayerController];
    
    [player_ prepareToPlay];
    [player_ setShouldAutoplay:self.isAutostartEnabled];
    
    // start the video for iOS4, prepareToPlay isn't enough to show the controls here
    PSPDF_IF_PRE_IOS5([player_ play];
                      if(!self.isAutostartEnabled) [player_ pause];)
}

/// page is hidden
- (void)didHidePage:(NSUInteger)page {
    if (player_.playbackState == MPMoviePlaybackStatePlaying) {
        [player_ pause];
    }
}

@end
