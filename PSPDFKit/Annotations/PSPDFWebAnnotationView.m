//
//  PSPDFWebAnnotationView.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFWebAnnotationView.h"

@implementation PSPDFWebAnnotationView {
    BOOL shadowsHidden_;
    NSUInteger requestCount_;
}

@synthesize annotation = annotation_;
@synthesize webView = webView_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (void)loadingStatusChanged_ {
    PSPDFLog(@"Finished loading %@", webView_.request);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        PSPDFRegisterObject(self);

        webView_ = [[UIWebView alloc] initWithFrame:self.bounds];
        webView_.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:webView_];
        webView_.delegate = self;
        webView_.scalesPageToFit = YES;
        
        // allow inline playback, even on iPhone
        webView_.allowsInlineMediaPlayback = YES;
    }
    return self;
}

- (void)dealloc {
    // "the deallocation problem" - it's not safe to dealloc a controler from a thread different than the main thread
    // http://developer.apple.com/library/ios/#technotes/tn2109/_index.html#//apple_ref/doc/uid/DTS40010274-CH1-SUBSECTION11
    NSAssert([NSThread isMainThread], @"Must run on main thread, see http://developer.apple.com/library/ios/#technotes/tn2109/_index.html#//apple_ref/doc/uid/DTS40010274-CH1-SUBSECTION11");
    PSPDFDeregisterObject(self);
    webView_.delegate = nil; // delegate is self here, so first set to nil before call stopLoading.
    [webView_ stopLoading];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)layoutSubviews {
    [super layoutSubviews];
    webView_.frame = self.bounds;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (BOOL)shadowsHidden {
	for (UIView *view in [webView_ subviews]) {
		if ([view isKindOfClass:[UIScrollView class]]) {
			for (UIView *innerView in [view subviews]) {
				if ([innerView isKindOfClass:[UIImageView class]]) {
					return [innerView isHidden];
				}
			}
		}
	}
	return NO;
}

- (void)setShadowsHidden:(BOOL)hide {
	if (shadowsHidden_ == hide) {
		return;
	}    
	shadowsHidden_ = hide;
    
	for (UIView *view in [webView_ subviews]) {
		if ([view isKindOfClass:[UIScrollView class]]) {
			for (UIView *innerView in [view subviews]) {
				if ([innerView isKindOfClass:[UIImageView class]]) {
					innerView.hidden = shadowsHidden_;
				}
			}
		}
	}
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIWebViewDelegate

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
	requestCount_--;
	if (requestCount_ == 0) {
		[self loadingStatusChanged_];
	}
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
	requestCount_--;
	if (requestCount_ == 0) {
		[self loadingStatusChanged_];
	}
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
	requestCount_++;
}

@end
