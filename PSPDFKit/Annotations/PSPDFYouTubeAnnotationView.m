//
//  PSPDFYouTubeAnnotationView.m
//  PSPDFKit
//
//  Copyright (c) 2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFYouTubeAnnotationView.h"
#import "PSPDFVideoAnnotationView.h"
#import "PSYouTubeExtractor.h"
#import "PSPDFKitGlobal.h"
#import "PSPDFAnnotation.h"
#import <objc/runtime.h>

@interface PSPDFYouTubeAnnotationView() {
    BOOL showNativeFirst_;
    PSYouTubeExtractor *extractor_;
}
@end

static char kPSPDFCachedYouTubeURLKey;

@implementation PSPDFYouTubeAnnotationView

@synthesize youTubeURL = youTubeURL_;
@synthesize youTubeMovieURL = youTubeMovieURL_;
@synthesize nativeView = nativeView_;
@synthesize setupNativeView = setupNativeView_;
@synthesize setupWebView = setupWebView_;
@synthesize moviePlayerController = moviePlayerController_;
@synthesize webView = webView_;
@synthesize error = error_;
@synthesize animated = animated_;
@synthesize autostartEnabled = autostartEnabled_;
@synthesize annotation = annotation_;

- (id)initWithYouTubeURL:(NSURL *)youTubeURL frame:(CGRect)frame annotation:(PSPDFAnnotation *)annotation showNativeFirst:(BOOL)showNativeFirst {
    if ((self = [super initWithFrame:frame])) {
        PSPDFRegisterObject(self);
        youTubeURL_ = youTubeURL;
        showNativeFirst_ = showNativeFirst;
        animated_ = YES;
        annotation_ = annotation;
        
        if ([annotation.options objectForKey:@"autostart"]) {
            self.autostartEnabled = [[annotation.options objectForKey:@"autostart"] boolValue];
        }
        
        // psst, undocumented stuff!
        if ([annotation.options objectForKey:@"showNativeFirst"]) {
            showNativeFirst_ = [[annotation.options objectForKey:@"showNativeFirst"] boolValue];
        }
        
        // like PSPDFKit 1.8 and earlier.
        BOOL legacy = NO;
        if ([annotation.options objectForKey:@"legacy"]) {
            legacy = [[annotation.options objectForKey:@"legacy"] boolValue];
        }
        
        // don't try to extract on iOS4.
        PSPDF_IF_PRE_IOS5(legacy = YES;)
        
        // fixin' invalid YouTube formats
        if([[youTubeURL absoluteString] rangeOfString:@"/v/"].length > 0) {
            youTubeURL_ = [NSURL URLWithString:[[youTubeURL absoluteString] stringByReplacingOccurrencesOfString:@"/v/" withString:@"/watch?v="]];
        }        
        if([[youTubeURL absoluteString] rangeOfString:@"/embed/"].length > 0) {
            youTubeURL_ = [NSURL URLWithString:[[youTubeURL absoluteString] stringByReplacingOccurrencesOfString:@"/embed/" withString:@"/watch?v="]];
        }
        
        __ps_weak PSPDFYouTubeAnnotationView *weakSelf = self;
        setupNativeView_ = ^{
            
#if defined(__i386__) || defined(__x86_64__)
            NSLog(@"------------------------------------------------------------------------------");
            NSLog(@"Note: If the embedded video crashes, it's a bug in Apple's Simulator. Please try on a real device.");
            NSLog(@"Referencing \"Error loading /System/Library/Extensions/AudioIPCDriver.kext/... Symbol not found: ___CFObjCIsCollectable.\"");
            NSLog(@"This is a known bug in Xcode 4.1+ / Lion");
            NSLog(@"This note will only show up in the i386 codebase and not on the device.");
            NSLog(@"------------------------------------------------------------------------------");
#endif            
            // always destroy & recreate, else we sometimes don't get a picture
            [weakSelf.moviePlayerController.view removeFromSuperview];
            MPMoviePlayerController *moviePlayerController = [[MPMoviePlayerController alloc] initWithContentURL:weakSelf.youTubeMovieURL];
            moviePlayerController.view.frame = weakSelf.bounds;
            moviePlayerController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;   
            [weakSelf insertSubview:moviePlayerController.view atIndex:0];
            weakSelf.moviePlayerController = moviePlayerController;
            
            if (weakSelf.youTubeMovieURL) {
                [weakSelf.moviePlayerController prepareToPlay];
                [weakSelf setAutostartEnabled:weakSelf.isAutostartEnabled];
            }
            
            // if there is a webview, remove it!
            if (weakSelf.webView) {
                [UIView animateWithDuration:weakSelf.isAnimated ? 0.3f : 0.f delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
                    weakSelf.webView.alpha = 0.f;
                } completion:^(BOOL finished) {
                    if (finished) {
                        [weakSelf.webView removeFromSuperview];
                        weakSelf.webView.delegate = nil;
                        weakSelf.webView = nil;
                    }
                }];
            }
        };
        
        setupWebView_ = ^{
            if (!weakSelf.webView) {
                
#if defined(__i386__) || defined(__x86_64__)
                NSLog(@"------------------------------------------------------------------------------");
                NSLog(@"Note: There is no YouTube plugin in the iPhone Simulator. View will be blank. Please test this on the device.");
                NSLog(@"------------------------------------------------------------------------------");
#endif
                UIWebView *webView = [[UIWebView alloc] initWithFrame:weakSelf.bounds];
                webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [weakSelf insertSubview:webView atIndex:0];
                // allow inline playback, even on iPhone
                webView.allowsInlineMediaPlayback = YES;
                weakSelf.webView = webView;
                
                // load plugin
                NSString *embedHTML = @"<html><head><style type=\"text/css\"> \
                body {background-color:transparent;color:white;}</style> \
                </head><body style=\"margin:0\"> \
                <embed id=\"yt\" src=\"%@\" type=\"application/x-shockwave-flash\" \
                width=\"%0.0f\" height=\"%0.0f\"></embed></body></html>";  
                NSString *html = [NSString stringWithFormat:embedHTML, [weakSelf.youTubeURL absoluteString], weakSelf.frame.size.width, weakSelf.frame.size.height]; 
                [webView loadHTMLString:html baseURL:nil];  
            }
            
            // remove MPMoviePlayerController
            if(weakSelf.moviePlayerController) {
                [UIView animateWithDuration:weakSelf.isAnimated ? 0.3f : 0.f delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
                    weakSelf.moviePlayerController.view.alpha = 0.f;
                } completion:^(BOOL finished) {
                    if(finished) {
                        [weakSelf.moviePlayerController.view removeFromSuperview];
                        weakSelf.moviePlayerController = nil;
                    }
                }];
            }
        };
        
        // try to access the cached resolved key.
        youTubeMovieURL_ = objc_getAssociatedObject(annotation_, &kPSPDFCachedYouTubeURLKey);
        if (youTubeMovieURL_) {
            if (setupNativeView_) {
                setupNativeView_();
            }
        }else {
            // like PSPDFKit 1.8 and earlier
            if (legacy) {
                if (setupWebView_) {
                    setupWebView_();
                }
            }else {
                // retains itself until either success or failure is called
                extractor_ = [PSYouTubeExtractor extractorForYouTubeURL:self.youTubeURL success:^(NSURL *URL) {
                    PSPDFLogVerbose(@"Finished extracting: %@", URL);
                    youTubeMovieURL_ = URL;
                    
                    // cache the value!
                    objc_setAssociatedObject(annotation_, &kPSPDFCachedYouTubeURLKey, URL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    
                    if (setupNativeView_) {
                        setupNativeView_();
                    }
                } failure:^(NSError *error) {
                    PSPDFLogWarning(@"Failed to query YouTube mp4: %@", error);
                    error_ = error;
                    if (setupWebView_) {
                        setupWebView_();
                    }
                }];
            }
        }
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    [extractor_ cancel];
    [moviePlayerController_ stop];
    moviePlayerController_.contentURL = nil;
    webView_ .delegate = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFAnnotationView

/// page is displayed
- (void)didShowPage:(NSUInteger)page {
    
    // invoke the view generation as soon as the view will be added to the screen
    if (!self.webView && !self.moviePlayerController) {
        if (showNativeFirst_) {
            if (setupNativeView_) {
                setupNativeView_();
            }
        }else {
            if (setupWebView_) {
                setupWebView_();
            }
        }
    }
    
    [moviePlayerController_ prepareToPlay];
    [moviePlayerController_ setShouldAutoplay:self.isAutostartEnabled];
    
    // start the video for iOS4, prepareToPlay isn't enough to show the controls here
    PSPDF_IF_PRE_IOS5([moviePlayerController_ play];
                      if(!self.isAutostartEnabled) [moviePlayerController_ pause];)
}

/// page is hidden
- (void)didHidePage:(NSUInteger)page {
    if (moviePlayerController_.playbackState == MPMoviePlaybackStatePlaying) {
        [moviePlayerController_ pause];
    }
}

@end
