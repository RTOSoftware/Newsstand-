//
//  PSPDFScrollView.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFViewController+Internal.h"
#import <QuartzCore/QuartzCore.h>
#import <MessageUI/MessageUI.h>

@interface PSPDFScrollView() <UIGestureRecognizerDelegate> {
    NSInteger memoryWarningCounter_;
    BOOL isShowingRightPage_;
}
@property(nonatomic, strong) PSPDFDocument *document;
@property(nonatomic, strong) UIView *compoundView;
@property(nonatomic, strong) PSPDFPageView *leftPage;
@property(nonatomic, strong) PSPDFPageView *rightPage;
- (void)layoutPages;
@end

@implementation PSPDFScrollView

@synthesize page = page_;
@synthesize leftPage = leftPage_;
@synthesize rightPage = rightPage_;
@synthesize document = document_;
@synthesize fitWidth = fitWidth_;
@synthesize compoundView = compoundView_;
@synthesize pdfController = pdfController_;
@synthesize dualPageMode = dualPageMode_;
@synthesize shadowEnabled = shadowEnabled_;
@synthesize shadowStyle = shadowStyle_;
@synthesize rotationActive = rotationActive_;
@synthesize doublePageModeOnFirstPage = doublePageModeOnFirstPage_;
@synthesize zoomingSmallDocumentsEnabled = zoomingSmallDocumentsEnabled_;
@synthesize scrollOnTapPageEndEnabled = scrollOnTapPageEndEnabled_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// hud and link-handling
- (void)singleTapped:(UITapGestureRecognizer *)gesture {
    PSPDFDocument *document = self.document;
    
    // get frontmost view, handle touches to a link annotation
    CGPoint localTouchPoint = [gesture locationInView:self];
    UIView *topmost = [self hitTest:localTouchPoint withEvent:nil];
    if ([topmost isKindOfClass:[PSPDFLinkAnnotationView class]]) {
        PSPDFLinkAnnotationView *annotationView = (PSPDFLinkAnnotationView *)topmost;
        PSPDFPageView *pageView = (PSPDFPageView *)annotationView.superview;
        if ([pageView isKindOfClass:[PSPDFPageView class]]) {
            // manually send event
            [annotationView flashBackground];
            CGPoint tapPosition = [gesture locationInView:annotationView];
            PSPDFPageInfo *pageInfo = [document pageInfoForPage:pageView.page];
            CGRect rectPage = [document rectBoxForPage:pageView.page];
            CGSize pageSize = CGSizeMake(rectPage.size.width * leftPage_.pdfScale, rectPage.size.height * leftPage_.pdfScale);
            CGPoint pdfPosition = [PSPDFTilingView convertViewPointToPDFPoint:tapPosition rect:pageInfo.pageRect rotation:pageInfo.pageRotation pageRect:pageView.pdfView.bounds];
            PSPDFPageCoordinates *pageCoordinates = [PSPDFPageCoordinates pageCoordinatesWithpdfPoint:pdfPosition screenPoint:[self.compoundView convertPoint:tapPosition fromView:pageView] viewPoint:tapPosition pageSize:pageSize zoomScale:self.zoomScale];
            
            // if the delegate did not handle the tap on the annotation,
            if (![self.pdfController delegateDidTapOnAnnotation:annotationView.annotation page:pageView.page info:pageInfo coordinates:pageCoordinates]) {
                // invoke default behaviour for annotation
                [self.pdfController handleTouchUpForAnnotationIgnoredByDelegate:annotationView];
            }    
        }
        return;
    }
    
    BOOL isLeftPage = YES;
    CGPoint touchPoint = [gesture locationInView:self.compoundView.superview];
    CGPoint correctedTouchPoint = touchPoint;
    
    // calculate real page size
    CGRect rectPage = [document rectBoxForPage:self.page];
    CGSize pageSize = CGSizeMake(rectPage.size.width * leftPage_.pdfScale, rectPage.size.height * leftPage_.pdfScale);
    
    // find out correct page
    NSUInteger pageIndex = self.page + 1;
    if (self.isDualPageMode) {
        pageIndex = [self.pdfController landscapePage:self.page]+1;
        // if we're at more than 50%x, it's the next page! (except on title)
        NSUInteger pageWidth = pageSize.width;
        
        // first site is special case OR last page
        if (pageIndex == [document pageCount]) {
        }else if (touchPoint.x >= pageWidth) {
            isLeftPage = NO;
            
            // first page is only pageRight_, but still index 1
            if (pageIndex != 1 || self.doublePageModeOnFirstPage) {
                pageIndex++;
            }
            
            correctedTouchPoint.x -= pageWidth; 
            
            // adapt calculations
            rectPage = [document rectBoxForPage:self.page+1];
            pageSize = CGSizeMake(rectPage.size.width * rightPage_.pdfScale, rectPage.size.height * rightPage_.pdfScale);
        }
    }
    
    __block BOOL touchProcessed = NO;
    
    // page starting at zero
    NSUInteger zeroStartingPage = pageIndex-1;
    
    // prepare check for pdf annotations
    PSPDFPageInfo *pageInfo = [document pageInfoForPage:zeroStartingPage];
    
    // on page 1, leftPage is nil, only rightPage is there.
    PSPDFPageView *pdfView = nil;
    
    if (self.pdfController.pageCurlEnabled) {
        pdfView = [self.pdfController pageViewForPage:zeroStartingPage];
        // attempt to get right page
        if (!isLeftPage) {
            PSPDFPageView *rightPageView = [self.pdfController pageViewForPage:zeroStartingPage+1];
            if (rightPageView) {
                pdfView = rightPageView;
            }
        }
    }else {
        pdfView = (isLeftPage && leftPage_) ? leftPage_ : rightPage_;
    }
    
    CGPoint tapPosition = [gesture locationInView:pdfView];    
    CGPoint pdfPosition = [PSPDFTilingView convertViewPointToPDFPoint:tapPosition rect:pageInfo.pageRect rotation:pageInfo.pageRotation pageRect:pdfView.bounds];
    PSPDFPageCoordinates *pageCoordinates = [PSPDFPageCoordinates pageCoordinatesWithpdfPoint:pdfPosition screenPoint:correctedTouchPoint viewPoint:tapPosition pageSize:pageSize zoomScale:self.zoomScale];
    
    // process delegate
    if (!touchProcessed) {
        touchProcessed = [pdfController_ delegateDidTapOnPageView:pdfView info:pageInfo coordinates:pageCoordinates];
    }
    
    // if touch is not used, show/hide HUD
    if (!touchProcessed) {
        if (self.zoomScale == 1.f) {
            CGFloat deviceWidth = self.pdfController.view.frame.size.width;
            if (touchPoint.x < deviceWidth/8 && self.isScrollOnTapPageEndEnabled) {
                if (![self.pdfController scrollToPreviousPageAnimated:YES]) {
                    [self.pdfController showControls];
                }else {
                    [self.pdfController hideControls];
                }
            }
            else if (touchPoint.x > 7*deviceWidth/8 && self.isScrollOnTapPageEndEnabled) {
                if (![self.pdfController scrollToNextPageAnimated:YES]) {
                    [self.pdfController showControls];
                }else {
                    [self.pdfController hideControls];
                }
            }else {
                [self.pdfController toggleControls];
            }
        }else {
            [self.pdfController toggleControls];                
        }
    }
}

// zoom out
- (void)tripleTapped:(UITapGestureRecognizer *)gesture {
    if (self.zoomScale > 1.f) {
        CGPoint touchPoint = [gesture locationInView:self];
        [self zoomToRect:CGRectMake(touchPoint.x, touchPoint.y, 4000, 4000) animated:YES];  
    }
}

// zoom in
#define kZoomSize (PSIsIpad() ? 350 : 100)
- (void)doubleTapped:(UITapGestureRecognizer *)gesture {
    if (self.zoomScale > self.minimumZoomScale) {
        [self tripleTapped:gesture];
    } else if (self.zoomScale < self.maximumZoomScale) {
        CGPoint touchPoint = [gesture locationInView:self];
        NSUInteger touchPointX = touchPoint.x < kZoomSize/2 ? 0 : touchPoint.x-kZoomSize/2;
        NSUInteger touchPointY = touchPoint.y < kZoomSize/2 ? 0 : touchPoint.y-kZoomSize/2;
        CGRect zoomRect = CGRectMake(touchPointX, touchPointY, kZoomSize, kZoomSize);
        PSPDFLog(@"pointed: %@ zooming to rect: %@", NSStringFromCGPoint(touchPoint), NSStringFromCGRect(zoomRect));
        [self zoomToRect:zoomRect animated:YES];
    }
}

// creates a CGPath for shadows. Can be overridden.
- (id)pathShadowForView:(UIView *)imgView {
    CGSize size = imgView.bounds.size;    
    UIBezierPath *path = nil;
    
    switch (shadowStyle_) {
        case PSPDFShadowStyleFlat: {
            CGFloat moveShadow = -12;
            path = [UIBezierPath bezierPathWithRect:CGRectMake(moveShadow, moveShadow, size.width+fabs(moveShadow/2), size.height+fabs(moveShadow/2))];
        }break;
            
        case PSPDFShadowStyleCurl: {
            CGFloat curlFactor = 15.0f;
            CGFloat shadowDepth = 5.0f;
            path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(0.0f, 0.0f)];
            [path addLineToPoint:CGPointMake(size.width, 0.0f)];
            [path addLineToPoint:CGPointMake(size.width, size.height + shadowDepth)];
            [path addCurveToPoint:CGPointMake(0.0f, size.height + shadowDepth)
                    controlPoint1:CGPointMake(size.width - curlFactor, size.height + shadowDepth - curlFactor)
                    controlPoint2:CGPointMake(curlFactor, size.height + shadowDepth - curlFactor)];
        }break;
            
        default:
            PSPDFLogError(@"Invalid style set for page shadow: %d", shadowStyle_);
            break;
    }
    
    // copy path, else ARC instantly deallocates the UIBezierPath backing store
    id cgPath = path ? (__bridge_transfer id)CGPathCreateCopy(path.CGPath) : nil;
    return cgPath;
}

- (void)configureShadow {    
    CALayer *backgroundLayer = self.compoundView.layer;
    
    if (self.isShadowEnabled) {
        backgroundLayer.shadowColor = [UIColor blackColor].CGColor;
        backgroundLayer.shadowOffset = PSIsIpad() ? CGSizeMake(10.0f, 10.0f) : CGSizeMake(8.0f, 8.0f); 
        backgroundLayer.shadowRadius = 4.0f;
        backgroundLayer.masksToBounds = NO;
        
        BOOL shouldUpdatePath = YES;
        if (self.isRotationActive && backgroundLayer.shadowPath) {
            CGRect currentRect = CGPathGetPathBoundingBox(backgroundLayer.shadowPath);
            CGRect newRect = CGPathGetPathBoundingBox((__bridge CGPathRef)[self pathShadowForView:self.compoundView]);
            
            if (newRect.size.width > currentRect.size.width || newRect.size.height > currentRect.size.height) {
                shouldUpdatePath = NO;
            }
        }
        if (shouldUpdatePath) {
            if (backgroundLayer.shadowOpacity == 0.f && backgroundLayer.shadowPath) {
                CABasicAnimation *theAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
                theAnimation.duration = 0.1f;
                theAnimation.fromValue = [NSNumber numberWithFloat:0.0f];
                theAnimation.toValue = [NSNumber numberWithFloat:0.7f];
                [backgroundLayer addAnimation:theAnimation forKey:@"shadowOpacity"];
            }
            backgroundLayer.shadowOpacity = 0.7f;
            backgroundLayer.shadowPath = (__bridge CGPathRef)[self pathShadowForView:self.compoundView];
        }else {
            backgroundLayer.shadowOpacity = 0.f;
        }
    }else {
        backgroundLayer.shadowOpacity = 0.f;        
        backgroundLayer.shadowPath = nil;
    }
}

- (CGSize)boundSize {
    CGSize parentBoundsSize = CGSizeZero;
    
    // TODO: why so complicated? Why do we need the controller here?
    PSPDFViewController *controller = self.pdfController;
    if (controller) {
        if (controller.pageCurlEnabled) {
            parentBoundsSize = self.bounds.size;
        }else {
            parentBoundsSize = controller.view.bounds.size;
        }
    }
    
    return parentBoundsSize;
}

// lazy-init
- (PSPDFPageView *)leftPage {
    if (!leftPage_) {
        leftPage_ = [[PSPDFPageView alloc] init];
        leftPage_.pdfView.hidden = self.isRotationActive;
        [self.compoundView addSubview:leftPage_];
    }
    return leftPage_;
}

// lazy-init
- (PSPDFPageView *)rightPage {
    if (!rightPage_) {
        rightPage_ = [[PSPDFPageView alloc] init];
        rightPage_.pdfView.hidden = self.isRotationActive;
        rightPage_.hidden = YES; // default-hide
        [self.compoundView addSubview:rightPage_];
    }
    return rightPage_;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        PSPDFRegisterObject(self);
        self.showsVerticalScrollIndicator = kPSPDFKitDebugScrollViews;
        self.showsHorizontalScrollIndicator = kPSPDFKitDebugScrollViews;
        self.bouncesZoom = YES;
        shadowStyle_ = PSPDFShadowStyleFlat;
        self.directionalLockEnabled = YES; // like iBooks
        self.decelerationRate = UIScrollViewDecelerationRateFast;
        [self setBackgroundColor:[UIColor clearColor]];
        
        if(kPSPDFKitDebugScrollViews) {
            self.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.8];
            self.alpha = 0.6f;
        }
        self.delegate = self;
        
        // for rotation - view resizes itself
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // needed for shadows in subviews
        self.clipsToBounds = NO;
        
        // disable scrolling to top
        self.scrollsToTop = NO;
        
        // zooming out
        UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tripleTapped:)];
        tripleTap.numberOfTapsRequired = 3;
        [self addGestureRecognizer:tripleTap];
        
        // zooming in
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
        doubleTap.numberOfTapsRequired = 2;
        [doubleTap requireGestureRecognizerToFail:tripleTap];
        [self addGestureRecognizer:doubleTap];
        
        // hud
        UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapped:)];
        singleTap.numberOfTapsRequired = 1;
        singleTap.delaysTouchesBegan = NO;
        singleTap.delaysTouchesEnded = NO;
        singleTap.delegate = self;
        [singleTap requireGestureRecognizerToFail:doubleTap];
        [self addGestureRecognizer:singleTap];
        
        // create compound view
        compoundView_ = [[UIView alloc] initWithFrame:CGRectZero];
        compoundView_.opaque = YES;
        self.compoundView.backgroundColor = [UIColor clearColor];
        [self addSubview:self.compoundView];
    }
    return self;
}

// this may be deallocated from a background thread, as PSPDFTilingView holds a reference on it
- (void)dealloc {
    PSPDFDeregisterObject(self);
    self.delegate = nil;
    pdfController_ = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Override layoutSubviews to center content

// also called upon rotation events
- (void)layoutSubviews {
    [super layoutSubviews];
    
    // center the image as it becomes smaller than the size of the screen
    CGSize boundsSize = [self boundSize];
    
    CGRect frameToCenter = self.compoundView.frame;
    if (frameToCenter.size.width == 0 || frameToCenter.size.height == 0) {
        // only warn with document set, else it's expected to have a zero frame
        if (self.document.isValid) {
            PSPDFLogWarning(@"Compount frame is zero, aborting!");
        }
        return;
    }
    
    // center horizontally
    if (frameToCenter.size.width < boundsSize.width)
        frameToCenter.origin.x = roundf((boundsSize.width - frameToCenter.size.width) / 2);
    else
        frameToCenter.origin.x = 0;
    
    // center vertically
    if (frameToCenter.size.height < boundsSize.height)
        frameToCenter.origin.y = roundf((boundsSize.height - frameToCenter.size.height) / 2);
    else
        frameToCenter.origin.y = 0;
    
    self.compoundView.frame = frameToCenter;
    [self configureShadow];    
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Memory

- (void)didReceiveMemoryWarning {
    PSPDFLogVerbose(@"memory warning...");
    
    // but if we remove cache every time, we are kept in an endless loop of memory warnings, releases, drawing, warning
    if (memoryWarningCounter_ > 3) {
        PSPDFLog(@"releasing CATiledLayer cache!");
        // http://stackoverflow.com/questions/1274680/clear-catiledlayers-cache-when-changing-images
        leftPage_.pdfView.layer.contents = nil;
        [leftPage_.pdfView.layer setNeedsDisplay];
        
        rightPage_.pdfView.layer.contents = nil;
        [rightPage_.pdfView.layer setNeedsDisplay];
        memoryWarningCounter_ = 0;
    }else {
        memoryWarningCounter_++;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.compoundView;
}

- (UIScrollView *)parentScrollView {
    UIScrollView *scrollView = (UIScrollView *)self.superview;
    while (scrollView && ![scrollView isKindOfClass:[UIScrollView class]]) {
        scrollView = (UIScrollView *)scrollView.superview;
    }
    
    return scrollView;
}

- (void)setParentScrollViewScrollPagingEnabled:(BOOL)enable {
    UIScrollView *parentScrollView = [self parentScrollView];
    parentScrollView.scrollEnabled = enable && self.pdfController.scrollingEnabled;    
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(float)scale {  
    // re-enable pan
    [self setParentScrollViewScrollPagingEnabled:YES];
    [self.compoundView setNeedsLayout];
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
    [self.pdfController hideControls];    
    
    // disable pan 
    [self setParentScrollViewScrollPagingEnabled:NO];    
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Configure scrollView to display new pdf page

- (void)releaseDocumentAndCallDelegate:(BOOL)callDelegate {
    [leftPage_ destroyPageAndRemoveFromView:YES callDelegate:callDelegate];
    [rightPage_ destroyPageAndRemoveFromView:YES callDelegate:callDelegate];
    leftPage_ = nil;
    rightPage_ = nil;
    
    // remove references
    self.document = nil;
    self.pdfController = nil;
}

- (CGFloat)scaleForImageSize:(CGSize)imageSize fitWidth:(BOOL)fitWidth {
    // don't calculate if imageSize is nil
    if (CGSizeEqualToSize(imageSize, CGSizeZero)) {
        return 1.0;
    }
    
    CGSize boundsSize = [self boundSize];
    
    // set up our content size and min/max zoomscale
    CGFloat xScale = boundsSize.width / imageSize.width;    // the scale needed to perfectly fit the image width-wise
    CGFloat yScale = boundsSize.height / imageSize.height;  // the scale needed to perfectly fit the image height-wise
    CGFloat minScale = fitWidth ? xScale : MIN(xScale, yScale);                 // use minimum of these to allow the image to become fully visible
    
    // on high resolution screens we have double the pixel density, so we will be seeing every pixel if we limit the
    // maximum zoom scale to 0.5.
    CGFloat maxScale = 1.f / [[UIScreen mainScreen] scale];
    
    // don't let minScale exceed maxScale. (If the image is smaller than the screen, we don't want to force it to be zoomed.) 
    if (minScale > maxScale && !self.isZoomingSmallDocumentsEnabled) {
        minScale = maxScale;
    }
    
    if (minScale > 10.0) {
        PSPDFLogWarning(@"Ridiculous high scale detected, limiting.");
        minScale = 10.0;
    }
    
    return minScale;
}

// used with rotation
- (void)switchPages {
    PSPDFPageView *tmpPage = leftPage_;
    leftPage_ = rightPage_;
    rightPage_ = tmpPage;
}

- (void)layoutPages {
    // be sure to kill any displaying CATiledLayers - fixes flickering problem on devices
    [leftPage_.pdfView resetLayer];
    [rightPage_.pdfView resetLayer];
    
    NSUInteger pageId = self.page;
    NSInteger leftPage = pageId;
    NSInteger rightPage = 0;
    
    // used for delegates
    BOOL newLeftPage = NO, newRightPage = NO;
    
    // only show double pages!
    if (self.isDualPageMode) {
        pageId *= 2; // we show two pages at once!
        
        if (self.doublePageModeOnFirstPage) {
            leftPage = pageId;
            rightPage = pageId+1;
        }else {
            leftPage = pageId-1;
            rightPage = pageId;
            // compensate for first page single in double page mode
            if (leftPage < 0) {
                leftPage++;
                rightPage = -1;
            }
        }
    }else {
        rightPage = -1;
    }
    
    // destroy left page if invalid (first page in dual page mode)
    if (leftPage < 0) {
        [leftPage_ destroyPageAndRemoveFromView:YES callDelegate:YES];
        leftPage_ = nil;
    }
    
    // if we're displaying the *right* page and switch t double page mode, and they snap, exchange
    if (leftPage_.page == rightPage) {
        [self switchPages];
    }
    
    CGRect compountViewRect;
    CGRect leftPageRect = CGRectZero;
    if (leftPage >= 0) {
        leftPageRect = [self.document rectBoxForPage:leftPage];
    }
    CGSize compountRawPdfSize = leftPageRect.size;
    CGRect rightPageRect = CGRectZero;
    if (self.isDualPageMode && rightPage < [self.document pageCount]) {
        rightPageRect = [self.document rectBoxForPage:rightPage];
        compountRawPdfSize = CGSizeMake(roundf(leftPageRect.size.width+rightPageRect.size.width), roundf(MAX(leftPageRect.size.height,rightPageRect.size.height)));
    }
    
    CGFloat scale = [self scaleForImageSize:compountRawPdfSize fitWidth:self.isFittingWidth];
    
    if (leftPage >= 0) {
        if(!self.leftPage.document || self.leftPage.page != leftPage) {newLeftPage = YES;}
        [self.leftPage displayDocument:self.document page:leftPage pageRect:leftPageRect scale:scale];
    }
    isShowingRightPage_ = [self isDualPageMode] && rightPage < [self.document pageCount] && rightPage >= 0;
    if (isShowingRightPage_) {
        if(!self.rightPage.document || self.rightPage.page != rightPage) {newRightPage = YES;}
        [self.rightPage displayDocument:self.document page:rightPage pageRect:rightPageRect scale:scale];
        
        CGFloat leftPageHeight = leftPage_ ? leftPage_.frame.size.height : 0.f;
        CGFloat rightPageHeight = rightPage_ ? rightPage_.frame.size.height : 0.f;
        CGFloat leftPageWidth = leftPage_ ? leftPage_.frame.size.width : 0.f;
        CGFloat rightPageWidth = rightPage_ ? rightPage_.frame.size.width : 0.f;
        compountViewRect = CGRectMake(0, 0, roundf(leftPageWidth + rightPageWidth), roundf(MAX(leftPageHeight, rightPageHeight)));
        rightPage_.alpha = 1.f;
        leftPage_.alpha = 1.f;   
        rightPage_.hidden = NO;
    }else {
        compountViewRect = leftPage_.frame;
        
        // hack: create right page to support super-smooth rotations (in exchange to some minor overhead)
        self.rightPage.frame = self.leftPage.frame;
        //        self.rightPage.hidden = YES;
        
        // if there is a rightPage (due to rotation) move it (but don't move if we use the right page in portrait)
        if ([self.pdfController isRightPageInDoublePageMode:leftPage_.page]) {
            CGRect frame = rightPage_.frame;
            frame.origin.x = leftPage_.frame.origin.x - leftPage_.frame.size.width;
            rightPage_.frame = frame;
        }else {
            CGRect frame = rightPage_.frame;
            frame.origin.x = leftPage_.frame.origin.x + leftPage_.frame.size.width;
            rightPage_.frame = frame;
        }
        
        // if we have documents that are not full-width, fade the page out
        if (leftPage_.frame.size.width < self.frame.size.width) {
            rightPage_.alpha = 0.f;
        }
    }
    // set rect for compound image view
    self.compoundView.frame = compountViewRect;
    
    if ([self isDualPageMode]) {
        CGRect frame = rightPage_.frame;
        frame.origin.x = roundf(leftPage_.frame.size.width);
        rightPage_.frame = frame;
    }
    
    // setup UIScrollView contentSize
    self.contentSize = self.compoundView.frame.size;
    
    CGSize size = PSPDFSizeForScale(leftPageRect, scale);
    leftPage_.frame = CGRectMake(0, 0, size.width, size.height); // make size equal        
    
    if (self.isDualPageMode) {
        size = PSPDFSizeForScale(rightPageRect, scale);
        rightPage_.frame = CGRectMake(leftPage_.frame.size.width, 0, size.width, size.height); // make size equal
    }
    
    // send delegate events
    if (newLeftPage)  { [self.pdfController delegateDidLoadPageView:leftPage_]; }
    if (newRightPage) { [self.pdfController delegateDidLoadPageView:rightPage_]; }
}

// not used in pageCurl mode
- (void)displayDocument:(PSPDFDocument *)aDocument withPage:(NSUInteger)pageId {
    PSPDFLogVerbose(@"%@ - %d", aDocument.title, pageId);
    self.document = aDocument;
    self.page = pageId;    
    float maxZoomScale = self.pdfController.maximumZoomScale;
    self.maximumZoomScale = maxZoomScale > 0 ? maxZoomScale : 5.f;
    self.minimumZoomScale = 1.f;
    self.zoomScale = 1.f;
    self.contentOffset = CGPointZero;
    
    // setup pages & calculate new center
    [self layoutPages];
    [self setNeedsLayout];
}

// control special events needed for rotation
- (void)setRotationActive:(BOOL)rotationActive {
    rotationActive_ = rotationActive;
    leftPage_.pdfView.hidden = rotationActive;
    rightPage_.pdfView.hidden = rotationActive;
    leftPage_.hidden = NO;
    rightPage_.hidden = NO;
    
    // hide right page after rotation is finished (rotationActive = NO)
    if (!rotationActive) {
        BOOL displayRightPage = isShowingRightPage_ && !rotationActive;
        rightPage_.hidden = !displayRightPage;
        
        // update shadow
        [self setNeedsLayout];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && [touch.view isKindOfClass:[UIButton class]]) {
        return NO;
    }
    return YES;
}

@end
