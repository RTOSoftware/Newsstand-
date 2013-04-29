//
//  PSPDFPagedScrollView.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFPagedScrollView.h"
#import "PSPDFPageViewController.h"
#import "PSPDFViewController.h"

@interface PSPDFScrollView (PSPDFInternal)
@property(nonatomic, strong) PSPDFDocument *document;
@end

@interface PSPDFPagedScrollView ()
@property(strong, readwrite) PSPDFPageViewController *pageController;
@end

@implementation PSPDFPagedScrollView

@synthesize pageController = pageController_;

static void *kPSPDFPagedScrollViewContext;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithPageViewController:(PSPDFPageViewController *)pageController {
    if ((self = [super initWithFrame:pageController.view.bounds])) {
        // already registered as sub-object
        pageController_ = pageController;
        pageController.scrollView = self;
        self.pdfController = pageController.pdfController;
        self.document = pageController.pdfController.document;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.delegate = self;
        self.maximumZoomScale = pageController.pdfController.maximumZoomScale;
        self.scrollOnTapPageEndEnabled = self.pdfController.scrollOnTapPageEndEnabled;
        self.shadowEnabled = NO; // shadow is drawn by pages themselves
        [self addSubview:pageController.view];
        
        // modify gesture recognizers to allow zooming (double tap) to not interfere with UIPageViewController's default prev/next tap gesture.
        for (UIGestureRecognizer *gestureRecognizer in pageController.gestureRecognizers) {
            if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
                UITapGestureRecognizer *tapGesture = (UITapGestureRecognizer *)gestureRecognizer;
                if (tapGesture.numberOfTapsRequired == 1) {
                    tapGesture.enabled = NO;
                }
            }
        }
        
        // use KVO to detect if PSPDFPageViewController gets deallocated.
        [pageController addObserver:self forKeyPath:NSStringFromSelector(@selector(pdfController)) options:0 context:&kPSPDFPagedScrollViewContext];
    }
    return self;
}

- (void)dealloc {
    [pageController_ removeObserver:self forKeyPath:NSStringFromSelector(@selector(pdfController))];
    self.delegate = nil;
    
// wtf of the day - if we keep that line, we get crashes like [PSPDFPagedScrollView release]: message sent to deallocated instance
//    pageController_ = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kPSPDFPagedScrollViewContext) {
        if (self.pageController.pdfController == nil) {
            self.pageController = nil;
        }
    }else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFScrollView

- (UIView *)compoundView {
    return pageController_.view;
}

@end
