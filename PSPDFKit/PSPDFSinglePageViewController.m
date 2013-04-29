//
//  PSPDFSinglePageViewController.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFSinglePageViewController.h"
#import "PSPDFViewController.h"
#import "PSPDFViewController+Internal.h"
#import "PSPDFScrollView.h"
#import "PSPDFPageView.h"
#import "PSPDFTilingView.h"
#import "PSPDFDocument.h"
#import <QuartzCore/QuartzCore.h>

// provides write-access to properites, needed in PSPDFPage
@interface PSPDFPageView (PSPDFInternal)
@property(nonatomic, assign) NSUInteger page;
@property(nonatomic, strong) PSPDFDocument *document;
@end

@implementation PSPDFSinglePageViewController

@synthesize pdfController = pdfController_;
@synthesize pageView = pageView_;
@synthesize page = page_;
@synthesize useSolidBackground = useSolidBackground_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (CGFloat)scaleForImageSize:(CGSize)imageSize {
    // don't calculate if imageSize is nil
    if (CGSizeEqualToSize(imageSize, CGSizeZero)) {
        return 1.0;
    }
    
    // use superview, as the view is changed to fit the pages
    CGSize boundsSize = self.view.superview.superview.superview.bounds.size;
    
    // as we "steal" the coordintes from above PSPDFPageViewController, re-calculate our real space
    if ([pdfController_ isDualPageMode]) {
        boundsSize = CGSizeMake(boundsSize.width/2, boundsSize.height);
    }
    
    // set up our content size and min/max zoomscale
    CGFloat xScale = boundsSize.width / imageSize.width;    // the scale needed to perfectly fit the image width-wise
    CGFloat yScale = boundsSize.height / imageSize.height;  // the scale needed to perfectly fit the image height-wise
    CGFloat minScale = MIN(xScale, yScale);                 // use minimum of these to allow the image to become fully visible
    
    // on high resolution screens we have double the pixel density, so we will be seeing every pixel if we limit the
    // maximum zoom scale to 0.5.
    CGFloat maxScale = 1.f / [[UIScreen mainScreen] scale];
    
    // don't let minScale exceed maxScale. (If the image is smaller than the screen, we don't want to force it to be zoomed.) 
    if (minScale > maxScale && !self.pdfController.isZoomingSmallDocumentsEnabled) {
        minScale = maxScale;
    }
    
    if (minScale > 10.0) {
        PSPDFLogWarning(@"Ridiculous high scale detected, limiting.");
        minScale = 10.0;
    }
    
    return minScale;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithPDFController:(PSPDFViewController *)pdfController page:(NSUInteger)page {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        pdfController_ = pdfController;
        page_ = page;
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    [pageView_ destroyPageAndRemoveFromView:YES callDelegate:NO];
    pageView_.scrollView.pdfController = nil;
    pdfController_ = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // transparency doesn't work very well here
    if (useSolidBackground_) {
        self.view.backgroundColor = self.pdfController.backgroundColor;
    }
    
    if(kPSPDFKitDebugScrollViews) {
        self.view.backgroundColor = [UIColor purpleColor];
        self.view.alpha = 0.7;
    }
    
    // don't load content if we're on an invalid page
    if (page_ < [pdfController_.document pageCount]) {
        pageView_ = [[PSPDFPageView alloc] init];
        pageView_.frame = self.view.bounds;
        pageView_.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        pageView_.shadowEnabled = self.pdfController.isShadowEnabled;
        // pageView needs to be prepared for the delegates
        pageView_.page = page_;
        pageView_.document = pdfController_.document;
        
        BOOL doublePageModeOnFirstPage = self.pdfController.doublePageModeOnFirstPage;
        BOOL isRightAligned = NO;
        if ([self.pdfController isDualPageMode]) {
            isRightAligned = ![self.pdfController isRightPageInDoublePageMode:page_];
        }
        
        // update shadow depending on position
        __ps_weak PSPDFPageView *weakPageView = pageView_;
        [pageView_ setUpdateShadowBlock:^(PSPDFPageView *pageView) {
            PSPDFPageView *strongPageView = weakPageView;
            CALayer *backgroundLayer = pageView.layer;
            BOOL shouldHideShadow = strongPageView.scrollView.pdfController.isRotationActive;
            backgroundLayer.shadowOpacity = shouldHideShadow ? 0.f : strongPageView.shadowOpacity;
            CGSize size = pageView.bounds.size; 
            CGFloat moveShadow = -12;
            CGRect bezierRect = CGRectMake(moveShadow, moveShadow, size.width+fabs(moveShadow/2), size.height+fabs(moveShadow/2));
            
            if ([strongPageView.scrollView.pdfController isDualPageMode]) {
                // don't trunicate shadow if we open the document.
                if (!isRightAligned && (doublePageModeOnFirstPage || pageView.page > 0)) {
                    bezierRect = CGRectMake(0, moveShadow, size.width+fabs(moveShadow/2)+moveShadow, size.height+fabs(moveShadow/2));
                }else {
                    bezierRect = CGRectMake(moveShadow, moveShadow, size.width+fabs(moveShadow/2)+moveShadow, size.height+fabs(moveShadow/2));
                }
            }
            
            UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectIntegral(bezierRect)];
            backgroundLayer.shadowPath = path.CGPath;
        }];        
    }    
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    if (!parent) {
        [pageView_ destroyPageAndRemoveFromView:NO callDelegate:YES];
    }
}

// called when the view frame changes. Recalculate the pageView frame.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
        
    // stop on invalid pages
    if (page_ == NSUIntegerMax || page_ >= [pdfController_.document pageCount]) {
        return;
    }
    
    PSPDFDocument *document = pdfController_.document;
    CGRect pageRect = [document rectBoxForPage:page_];
    CGFloat scale = [self scaleForImageSize:pageRect.size];
    
    pageView_.frame = self.view.bounds;
    [pageView_ displayDocument:document page:page_ pageRect:pageRect scale:scale];
    
    // center view and position to the center
    CGSize viewSize = self.view.bounds.size;
    CGFloat leftPos = (viewSize.width - pageView_.frame.size.width)/2;
    
    // for dual page mode, align the pages like a magazine
    if ([self.pdfController isDualPageMode]) {
        BOOL shouldAlignRight = ![self.pdfController isRightPageInDoublePageMode:page_];
        leftPos = shouldAlignRight ? viewSize.width-pageView_.frame.size.width : 0.f;
    }
    pageView_.frame = CGRectIntegral(CGRectMake(leftPos, (viewSize.height - pageView_.frame.size.height)/2, pageView_.frame.size.width, pageView_.frame.size.height));
    [self.view addSubview:self.pageView];
    PSPDFLogVerbose(@"site %d frame: %@ pageView:%@", self.page, NSStringFromCGRect(self.view.frame), NSStringFromCGRect(pageView_.frame));
    
    // send delegate events
    [self.pdfController delegateDidLoadPageView:pageView_];
}

- (void)viewDidUnload {
    [super viewDidUnload];
    
    [pageView_ destroyPageAndRemoveFromView:YES callDelegate:YES];
    pageView_ = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setPdfController:(PSPDFViewController *)pdfController {
    pdfController_ = pdfController;
    pageView_.scrollView.pdfController = pdfController;
}

@end
