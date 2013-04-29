//
//  PSPFScrobbleBar.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import <QuartzCore/QuartzCore.h>

#define kPSPDFScrobbleThumbSize CGSizeMake(18.f, 25.f)
#define kPSPDFScrobbleThumbMarkerSizeMultiplikator 1.4
#define kPSPDFScrobbleThumbOuterMargin 5
#define kPSPDFScrobbleThumbMargin 5
#define kPSPDFScrobblePointerAnimationDuration 0.3f
#define kPSPDFScrobbleBarHeight 44.f

#define kPSPDFScrobbleThumbMarkerSize CGSizeMake(roundf(kPSPDFScrobbleThumbSize.width*kPSPDFScrobbleThumbMarkerSizeMultiplikator), roundf(kPSPDFScrobbleThumbSize.height*kPSPDFScrobbleThumbMarkerSizeMultiplikator))

@interface PSPDFScrobbleBar() {
    NSInteger pageMarkerPage_;
    NSUInteger thumbCount_;
    NSInteger lastTouchedPage_;
    UIImageView *positionImage_;
    UIImageView *positionImage2_;
    NSMutableDictionary *imageViews_;    // NSNumber (page) -> UIImageView
    BOOL touchInProgress_;
}
- (void)setPageInternal:(NSUInteger)page;
@property(nonatomic, assign, getter=isViewLocked) BOOL viewLocked; // for animation
@end

@implementation PSPDFScrobbleBar

@synthesize pdfController = pdfController_;
@synthesize viewLocked = viewLocked_;
@synthesize toolbar = toolbar_;
@synthesize page = page_;

static void *kPSPDFKVOToken;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// availble width minus outer margins
- (CGFloat)availableWidth {
    CGFloat availableWidth = self.frame.size.width-2*kPSPDFScrobbleThumbOuterMargin;
    return availableWidth;
}

- (CGFloat)contentWidth {
    CGFloat contentWidth = roundf(thumbCount_*kPSPDFScrobbleThumbSize.width+(thumbCount_-1.f)*kPSPDFScrobbleThumbMargin);
    return contentWidth;
}

- (CGFloat)leftBorder {
    NSUInteger leftBorderForCentering = 0;
    CGFloat contentWidth = [self contentWidth];
    CGFloat availableWidth = [self availableWidth];
    if (contentWidth < availableWidth) {
        leftBorderForCentering = floor((availableWidth - contentWidth)/2.f);
    }
    leftBorderForCentering += kPSPDFScrobbleThumbOuterMargin;
    return leftBorderForCentering;
}

- (BOOL)shouldShowTwoPageMarkerForPage:(NSUInteger)page {
    BOOL showTwo = NO;
    if([self.pdfController isDualPageMode]) {
        if (page > 0 && [self.pdfController isRightPageInDoublePageMode:page]) {
            page--;
        }
        showTwo = page+1 < [self.pdfController.document pageCount] && !(page == 0 && !self.pdfController.isDoublePageModeOnFirstPage);
    }
    return showTwo;
}

- (CGFloat)leftPosForThumbSize:(CGSize)thumbSize page:(NSUInteger)page {
//    BOOL shouldShowTwoPageMarkerForPage = [self shouldShowTwoPageMarkerForPage:self.page]; // don't use page as this would return differently for a second page
    CGFloat thumbWidth = kPSPDFScrobbleThumbSize.width;// * (shouldShowTwoPageMarkerForPage ? 2 : 1);
    NSUInteger pageCount = MAX(1, (NSInteger)[self.pdfController.document pageCount] - 1);
    CGFloat markerPos = roundf([self leftBorder] - kPSPDFScrobbleThumbMargin/2.f - 1.f + page/(CGFloat)pageCount * ([self contentWidth] - thumbWidth));
    return markerPos;
}

- (void)updatePageMarkerForced:(BOOL)forced {
    if (!forced && self.hidden) {
        return;
    }
    
    // check if we're on a right page, don't display wrong page combinations in double page mode
    NSInteger page = self.page;
    if ([self.pdfController isDualPageMode] && [self.pdfController isRightPageInDoublePageMode:page] && page > 0) {
        page--;
    }
    
    if (pageMarkerPage_ != self.page || forced) {
        NSUInteger pageCount = [self.pdfController.document pageCount];        
        if (pageCount) {
            CGSize thumbSize = kPSPDFScrobbleThumbMarkerSize;
            UIImage *thumbImage = [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:self.pdfController.document page:page size:PSPDFSizeTiny];
            if (thumbImage) {
                CGFloat scale = [UIImage pspdf_scaleForImageSize:thumbImage.size bounds:kPSPDFScrobbleThumbMarkerSize];
                thumbSize = CGSizeMake(roundf(thumbImage.size.width * scale), roundf(thumbImage.size.height * scale));
            }
            
            CGFloat markerPos = [self leftPosForThumbSize:thumbSize page:page];
            CGRect markerFrame = CGRectMake(markerPos,
                                            floorf((self.frame.size.height-thumbSize.height)/2.f),
                                            thumbSize.width,
                                            thumbSize.height);
            
            positionImage_.frame = markerFrame;
            positionImage_.image = thumbImage;
        }
        positionImage_.hidden = !pageCount;
        pageMarkerPage_ = page;
        
        // do we have a second page?
        positionImage2_.hidden = YES;
        BOOL shouldShowTwoPageMarker = [self shouldShowTwoPageMarkerForPage:page];
        if(shouldShowTwoPageMarker) {
            CGSize thumbSize = kPSPDFScrobbleThumbMarkerSize;
            UIImage *thumbImage = [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:self.pdfController.document page:page+1 size:PSPDFSizeTiny];
            if (thumbImage) {
                CGFloat scale = [UIImage pspdf_scaleForImageSize:thumbImage.size bounds:kPSPDFScrobbleThumbMarkerSize];
                thumbSize = CGSizeMake(roundf(thumbImage.size.width * scale), roundf(thumbImage.size.height * scale));
            }
            
            CGFloat markerPos = [self leftPosForThumbSize:thumbSize page:page];
            CGRect markerFrame = CGRectMake(markerPos + positionImage_.frame.size.width - 1.f,
                                            floorf((self.frame.size.height-thumbSize.height)/2.f),
                                            thumbSize.width,
                                            thumbSize.height);
            
            positionImage2_.frame = markerFrame;
            positionImage2_.image = thumbImage;    
            positionImage2_.hidden = !pageCount;
        }
    }
}

- (void)updatePageMarker {
    [self updatePageMarkerForced:NO];
}

- (void)updateToolbarPositionAnimated:(BOOL)animated forced:(BOOL)forced {
    BOOL isValidDocument = pdfController_.document.isValid;
    BOOL shouldShow = pdfController_.viewMode == PSPDFViewModeDocument && isValidDocument && (self.alpha < 0.99f || forced);
    BOOL shouldHide = (pdfController_.viewMode == PSPDFViewModeThumbnails || !isValidDocument) && (self.alpha > 0.f || forced);
    
    if (shouldShow || shouldHide) {
        [self updatePageMarker];
        self.viewLocked = YES;
        [UIView animateWithDuration:animated ? 0.25f : 0.f delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
            if (shouldShow) {
                self.alpha = 1.f;
                self.frame = CGRectMake(0, pdfController_.view.frame.size.height-kPSPDFScrobbleBarHeight, pdfController_.view.frame.size.width, kPSPDFScrobbleBarHeight);
            }else {
                self.alpha = 0.f;
                self.frame = CGRectMake(0, pdfController_.view.frame.size.height, pdfController_.view.frame.size.width, kPSPDFScrobbleBarHeight);
            }
            self.viewLocked = NO;
        } completion:nil];
    }
}

- (CGRect)rectForThumb:(CGSize)thumbSize withImageSize:(CGSize)imageSize position:(NSInteger)position {
    CGSize newThumbSize = thumbSize;
    if (!CGSizeEqualToSize(imageSize, CGSizeZero)) {
        CGFloat scale = [UIImage pspdf_scaleForImageSize:imageSize bounds:kPSPDFScrobbleThumbSize];
        newThumbSize = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
    }
    
    CGRect rect = CGRectMake([self leftBorder]+position*thumbSize.width+position*kPSPDFScrobbleThumbMargin, 
                             floor((self.frame.size.height-newThumbSize.height)/2.f), 
                             newThumbSize.width,
                             newThumbSize.height);
    return rect;
}

- (BOOL)processTouch:(UITouch *)touch animated:(BOOL)animated {
    CGPoint tapPoint = [touch locationInView:self];
    NSUInteger pageCount = [self.pdfController.document pageCount];
    NSUInteger page = 0;
    CGFloat minimumLeft = [self leftBorder] + kPSPDFScrobbleThumbSize.width/2;
    if (tapPoint.x > minimumLeft) {
        page = floor((tapPoint.x - minimumLeft)/([self contentWidth] - kPSPDFScrobbleThumbSize.width) * pageCount);
    }
    if (page >= pageCount) {
        page = pageCount-1;
    }
    
    // only scroll if page has changed
    if (lastTouchedPage_ != page) {        
        // checks for double page mode
        BOOL dualPageMode = [self.pdfController isDualPageMode];
        if (!dualPageMode || abs(lastTouchedPage_ - page) > 1 ||
            ((lastTouchedPage_ > page && !(dualPageMode && [self.pdfController isRightPageInDoublePageMode:page+1])) ||
             (lastTouchedPage_ < page && !(dualPageMode && [self.pdfController isRightPageInDoublePageMode:page])))) {
                PSPDFLogVerbose(@"scrolling to page: %d", page);
                [self.pdfController scrollToPage:page animated:(animated && PSPDFShouldAnimate()) hideHUD:NO];
            }
        lastTouchedPage_ = page;
        return YES;
    }else {
        return NO;
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    lastTouchedPage_ = -1;
    [self processTouch:[touches anyObject] animated:YES];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if([self processTouch:[touches anyObject] animated:YES]) {
        touchInProgress_ = YES;
        
        // set page internal with result, prevent animation
        [self setPageInternal:lastTouchedPage_];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    touchInProgress_ = NO;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    touchInProgress_ = NO;
}

// prepare a template UIImageView
- (UIImageView *)emptyThumbImageView {
    UIImageView *pageImage = [[UIImageView alloc] initWithFrame:CGRectZero];
    pageImage.backgroundColor = [UIColor colorWithRed:0.6f green:0.6f blue:0.6f alpha:0.7f];
    pageImage.layer.borderColor = [UIColor blackColor].CGColor;
    pageImage.layer.borderWidth = 1.f;
    return pageImage;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        imageViews_ = [[NSMutableDictionary alloc] init];
        page_ = 0;
        pageMarkerPage_ = -1;
        
        // clip images, don't bleed out
        self.clipsToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        
        // translucent black toolbar
        toolbar_ = [[UIToolbar alloc] init];
        toolbar_.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        toolbar_.barStyle = UIBarStyleBlackTranslucent;
        toolbar_.tintColor = [UIColor blackColor];
        toolbar_.alpha = kPSPDFKitHUDTransparency;
        [self addSubview:toolbar_];
        
        // register master position marker
        positionImage_  = [self emptyThumbImageView];
        positionImage2_ = [self emptyThumbImageView];
        
        [self addSubview:positionImage_];
        [self addSubview:positionImage2_];
        
        // listen for cache hits
        [[PSPDFCache sharedPSPDFCache] addDelegate:self];
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    pdfController_ = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateToolbarForced) object:nil];
    [[PSPDFCache sharedPSPDFCache] removeDelegate:self];
}

- (NSArray *)kvoValues {
    // viewModeAnimated is a special token to inform us of an _animated_ change of the viewMode.
    return [NSArray arrayWithObjects:NSStringFromSelector(@selector(realPage)), NSStringFromSelector(@selector(viewMode)), @"viewModeAnimated", nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kPSPDFKVOToken) {
        // performance: only update if visible!
        if (!self.hidden) {
            [self setPage:pdfController_.realPage];
            [self updatePageMarker];
            
            // no need to update toolbar position on a page change
            if (![keyPath isEqualToString:NSStringFromSelector(@selector(realPage))]) {
                BOOL animated = [keyPath isEqualToString:@"viewModeAnimated"];
                [self updateToolbarPositionAnimated:animated forced:NO];
                [self updateToolbar];
            }
        }
        // ensure bar is hidden if no document is set
        self.hidden = pdfController_.document == nil;
    }else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)setPdfController:(PSPDFViewController *)pdfController {
    if(pdfController != pdfController_) {
        PSPDFViewController *oldController = pdfController_;
        pdfController_ = pdfController;
        toolbar_.tintColor = pdfController.tintColor;
        [[self kvoValues] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [oldController removeObserver:self forKeyPath:obj];
            [pdfController addObserver:self forKeyPath:obj options:0 context:&kPSPDFKVOToken];
        }];
        if (pdfController) {
            [self updateToolbarPositionAnimated:NO forced:YES];
            [self updateToolbar];
        }
    }
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self setPage:pdfController_.realPage];
    [self updatePageMarker];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updatePageMarker];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    
    if (!self.isViewLocked) {
        pageMarkerPage_ = -1; // reset
        
        // don't update if controller is not even set!
        if (pdfController_) {
            [self updateToolbar];
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

// use queuing system to reduce calls
- (void)updateToolbar {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateToolbarForced) object:nil];
    [self performSelector:@selector(updateToolbarForced) withObject:nil afterDelay:0.f];
}

// create the thumbnails!
- (void)updateToolbarForced {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateToolbarForced) object:nil];
    
    // clear old views
    for (UIImageView *imageView in [imageViews_ allValues]) {
        [imageView removeFromSuperview];
    }
    [imageViews_ removeAllObjects];
    
    // calculate how many thumbs we can display
    NSUInteger pageCount = [self.pdfController.document pageCount];
    NSUInteger maxThumbCount = (self.frame.size.width-2.f*kPSPDFScrobbleThumbOuterMargin) / (CGFloat)(kPSPDFScrobbleThumbSize.width+kPSPDFScrobbleThumbMargin);
    thumbCount_ = MIN(pageCount, maxThumbCount);
    PSPDFLogVerbose(@"Showing %d thumbnails.", thumbCount_);
    
    // build reversed, to have proper caching requests in FIFO stack
    NSInteger lastPage = pageCount;
    for (int i = thumbCount_-1; i >= 0; i--) {
        
        // determine which page we show
        NSInteger page = ceil(pageCount * (i/(CGFloat)(thumbCount_-1)));
        while (page >= lastPage && page > 0) {
            page--;
        }
        lastPage = page;
        
        // create new UIImageView if not yet in dict
        UIImageView *pageImage = [imageViews_ objectForKey:[NSNumber numberWithInteger:page]];
        if (!pageImage) {
            pageImage = [self emptyThumbImageView];
            
            // may return nil, callback later with PSPDFCacheDelegate
            pageImage.image = [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:self.pdfController.document page:page size:PSPDFSizeTiny];
            pageImage.tag = i; // trick to remember the page.
            
            // save in dict
            [imageViews_ setObject:pageImage forKey:[NSNumber numberWithInteger:page]];
            [self addSubview:pageImage];
        }
        
        pageImage.frame = [self rectForThumb:kPSPDFScrobbleThumbSize withImageSize:pageImage.image ? pageImage.image.size : CGSizeZero position:i];
    }
    
    // position marker has to be frontmost
    [self bringSubviewToFront:positionImage2_];
    [self bringSubviewToFront:positionImage_];
    [self updatePageMarkerForced:YES];
    [self updateToolbarPositionAnimated:NO forced:YES];
}

- (void)setPageInternal:(NSUInteger)page {
    page_ = page;
    
    // perform after slight delay, performance. only update if visible!
    if (!self.hidden) {
        [self setNeedsLayout];
    }    
}

- (void)setPage:(NSUInteger)page {
    if (!touchInProgress_) {
        [self setPageInternal:page];
    }
}

- (void)animateImageView:(UIImageView *)imageView newImage:(UIImage *)image {
    // build animation block
    CATransition *transition = [CATransition animation];
    transition.duration = 0.25f;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    transition.type = kCATransitionFade;
    [imageView.layer addAnimation:transition forKey:@"image"];
    
    // set new image
    imageView.image = image;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFCacheDelegate

- (void)didCachePageForDocument:(PSPDFDocument *)document page:(NSUInteger)page image:(UIImage *)cachedImage size:(PSPDFSize)size {
    // only process if we're on a window and it's the tiny size
    if (self.window && size == PSPDFSizeTiny && document == self.pdfController.document) {
        UIImageView *imageView = [imageViews_ objectForKey:[NSNumber numberWithInteger:page]];
        if (imageView) {
            [self animateImageView:imageView newImage:cachedImage];
            
            // potentially update frame as soon as image has been loaded properly
            imageView.frame = [self rectForThumb:kPSPDFScrobbleThumbSize withImageSize:cachedImage.size position:imageView.tag];
        }
        
        // update marker
        if (self.page == page || self.page+1 == page || self.page-1 == page) {
            [self updatePageMarkerForced:YES];
        }
    }
}

@end
