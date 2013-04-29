//
//  PSPDFPDFPageView.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFViewController+Internal.h"
#import "PSPDFLinkAnnotationView.h"
#import "PSPDFHighlightAnnotationView.h"
#import <QuartzCore/QuartzCore.h>

@interface PSPDFPageView() {
    NSMutableDictionary *annotationViews_;
    CGPDFDocumentRef pdfDocument_;
    CGPDFPageRef pdfPage_;
}

@property(nonatomic, assign) NSUInteger page;
@property(nonatomic, strong) PSPDFDocument *document;
@property(nonatomic, assign) CGFloat pdfScale;
@property(nonatomic, strong) PSPDFTilingView *pdfView;
@property(nonatomic, strong) UIImageView *backgroundImageView;

/// if page is no longer used, mark it as destroyed. (even if blocks hold onto it)
@property(nonatomic, getter=isDestroyed) BOOL destroyed;
@end

@implementation PSPDFPageView

@synthesize page = page_;
@synthesize document = document_;
@synthesize backgroundImageView = backgroundImageView_;
@synthesize pdfView = pdfView_;
@synthesize pdfScale = pdfScale_;
@synthesize destroyed = destroyed_;
@synthesize loadThumbnailsOnMainThread = loadThumbnailsOnMainThread_;
@synthesize shadowEnabled = shadowEnabled_;
@synthesize updateShadowBlock = updateShadowBlock_;
@synthesize shadowOpacity = shadowOpacity_;
@dynamic scrollView;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - private

dispatch_queue_t pspdf_get_image_background_queue(void);
dispatch_queue_t pspdf_get_image_background_queue(void) {
	static dispatch_once_t once;
	static dispatch_queue_t image_loader_queue;
	dispatch_once(&once, ^{
		image_loader_queue = dispatch_queue_create("com.petersteinberger.pspdfkit.imageloader", NULL);
	});
	return image_loader_queue;
}

- (void)startCachingDocument {
    // cache page, make it an async call
    PSPDFDocument *aDocument = self.document;
    if (aDocument) {
        [[PSPDFCache sharedPSPDFCache] cacheDocument:aDocument startAtPage:self.page size:PSPDFSizeNative];
    }
}

// load page annotations from the pdf.
- (void)loadPageAnnotations {
    if (!self.document) {
        return; // document removed? don't try to load annotations!
    }
    
    // ensure annotations are already loaded; else load then in a background thread
    // If we don't check for annotationParser, this could result in an endless loop!
    if (self.document.annotationParser && ![self.document.annotationParser hasLoadedAnnotationsForPage:self.page]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.document.annotationParser annotationsForPage:self.page filter:0];
            // always call back to main queue, so we don't get released on a background thread.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self loadPageAnnotations];
            });
        });
        return;
    }
    PSPDFLogVerbose(@"Adding annotations for page: %d", self.page);
    NSArray *annotations = [self.document.annotationParser annotationsForPage:self.page filter:PSPDFAnnotationFilterOverlay | PSPDFAnnotationFilterLink];
    PSPDFLogVerbose(@"dispaying annotations: %@", annotations);
    
    PSPDFViewController *pdfController = self.scrollView.pdfController;
    for (PSPDFAnnotation *annotation in annotations) {
        BOOL shouldDisplay = [pdfController delegateShouldDisplayAnnotation:annotation onPageView:self];
        if(shouldDisplay) {
            CGRect annotationRect = [annotation rectForPageRect:self.bounds];
            
            // sanity check - rect can't be larger than the page.
            annotationRect = CGRectMake(MAX(annotationRect.origin.x, 0), MAX(annotationRect.origin.y, 0),
                                        MIN(annotationRect.size.width, self.bounds.size.width), MIN(annotationRect.size.height, self.bounds.size.height));
            
            PSPDFLogVerbose(@"anntation rect %@ (bounds: %@)", NSStringFromCGRect(annotationRect), NSStringFromCGRect(self.bounds));
            
            // check if the annotation is already created
            UIView <PSPDFAnnotationView> *annotationView = [annotationViews_ objectForKey:annotation.uid];
            if (annotationView) {
                annotationView.frame = annotationRect;
            }else {
                
                // create annotation using document's annotationParser
                annotationView = [self.document.annotationParser createAnnotationViewForAnnotation:annotation frame:annotationRect];
                
                // add support for deprecated delegate
                if (annotation.type == PSPDFAnnotationTypeCustom) {
                    annotationView = [pdfController delegateViewForAnnotation:annotation onPageView:self];
                    annotationView.frame = annotationRect;
                }
                
                // call delegate with created annotation, let user modify/return a new one
                annotationView = [pdfController delegateAnnotationView:annotationView forAnnotation:annotation onPageView:self];
                
                if (annotationView) {
                    [annotationViews_ setObject:annotationView forKey:annotation.uid];
                    [pdfController delegateWillShowAnnotationView:annotationView onPageView:self];
                    
                    [self insertSubview:annotationView aboveSubview:pdfView_];
                    
                    // smooth annotation animation
                    CGFloat animationDuration = self.scrollView.pdfController.annotationAnimationDuration;
                    if (animationDuration > 0.01f) {
                        annotationView.alpha = 0.f;
                        [UIView animateWithDuration:animationDuration delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
                            annotationView.alpha = 1.f;
                        } completion:^(BOOL finished) {
                            [pdfController delegateDidShowAnnotationView:annotationView onPageView:self];
                        }];
                    }else {
                        // don't animate, call delegate directly
                        [pdfController delegateDidShowAnnotationView:annotationView onPageView:self];
                    }
                }
            }
            
            // call up delegate
            if ([annotationView respondsToSelector:@selector(didShowPage:)]) {
                [(id<PSPDFAnnotationView>)annotationView didShowPage:self.page];
            }
        }
    }
}

- (void)callAnnotationVisibleDelegateToShow:(BOOL)show {
    // update show/hide info on all loaded annotations
    // iterates over all subviews that conform to PSPDFAnnotationView, even custom objects that are no pdf annotations.
    for (UIView *subview in self.subviews) {
        if ([subview conformsToProtocol:@protocol(PSPDFAnnotationView)]) {
            if (!show) {
                // call up delegate
                if ([subview respondsToSelector:@selector(didHidePage:)]) {
                    [(id<PSPDFAnnotationView>)subview didHidePage:self.page];
                }
            }else {
                // call up delegate
                if ([subview respondsToSelector:@selector(didShowPage:)]) {
                    [(id<PSPDFAnnotationView>)subview didShowPage:self.page];
                }
            }
        }
    }    
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if ((self = [super init])) {
        NSAssert([NSThread isMainThread], @"Must run on main thread (init PSPDFPageView)");
        PSPDFRegisterObject(self);
        
        // cache for annotation objects
        annotationViews_ = [[NSMutableDictionary alloc] init];
        
        // make transparent
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        shadowOpacity_ = 0.7f;
        
        // setup background image view
        backgroundImageView_ = [[UIImageView alloc] initWithImage:nil];
        backgroundImageView_.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        backgroundImageView_.opaque = YES;
        [self addSubview:backgroundImageView_];
        
        // create pdf view (foreground)
        pdfView_ = [[PSPDFTilingView alloc] initWithFrame:CGRectZero];
        pdfView_.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        pdfView_.pdfPage = self;
        if (kPSPDFKitDebugScrollViews) {
            pdfView_.alpha = 0.5f;
        }
        [self addSubview:pdfView_];
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    pdfView_.pdfPage = nil;
    if (!destroyed_) {
        // remove delegate, and wait for threads to finish drawing.
        // we *might* be not in main, so don't perform any UIKit modifications
        ((CATiledLayer *)[self.pdfView layer]).delegate = nil;
        ((CATiledLayer *)[self.pdfView layer]).contents = nil;    
    }
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startCachingDocument) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadPageAnnotations) object:nil];    
}

- (NSString *)description {
    NSString *defaultDescription = [super description]; // UIView's default description
    NSString *description = [NSString stringWithFormat:@"%@ (page: %d, document: %@)", defaultDescription, self.page, self.document];
    return description;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setShadowOpacity:(float)shadowOpacity {
    shadowOpacity_ = shadowOpacity;
    [self setNeedsLayout]; // rebuild shadow
}

// dynamically search for scrollView
- (PSPDFScrollView *)scrollView {
    PSPDFScrollView *scrollView = (PSPDFScrollView *)self.superview;
    while (scrollView && ![scrollView isKindOfClass:[PSPDFScrollView class]]) {
        scrollView = (PSPDFScrollView *)scrollView.superview;
    }
    return scrollView;
}

- (void)displayDocument:(PSPDFDocument *)document page:(NSUInteger)page pageRect:(CGRect)pageRect scale:(CGFloat)scale {
    self.document = document;
    self.page = page;
    self.pdfScale = scale;
    self.backgroundImageView.backgroundColor = [document backgroundColorForPage:page];
    
    // prevents NaN-crashes
    if (pageRect.size.width < 10 || pageRect.size.height < 10) {
        if ([document pageCount]) {
            PSPDFLogWarning(@"Invalid page rect given: %@ (stopping rendering here)", NSStringFromCGRect(pageRect));
        }
        return;
    }
    
    pageRect.size = PSPDFSizeForScale(pageRect, scale);
    
    // configure CATiledLayer
    self.frame = pageRect;
    self.pdfView.document = document;
    self.pdfView.page = page;
    
    // if full-size pageimage is in memory, use it -> insta-sharp!
    UIImage *backgroundImage = [[PSPDFCache sharedPSPDFCache] imageForDocument:document page:page size:PSPDFSizeNative];
    
    // call delegate if pdfController is not nil
    if (backgroundImage) {        
        [self.scrollView.pdfController delegateDidRenderPageView:self];
    }
    
    // fallback to thumbnail image, if it's on memory or on disk
    if (!backgroundImage) {
        
        // Experimental support for non-mainthread loading of background thumbs,
        // to remove even more load from the main thread. (but may flashes images)
        if (loadThumbnailsOnMainThread_) {
            // this may block the main thread for a but, but we don't wanna flash-in the thumbnail as soon as its there.
            backgroundImage = [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:document page:page size:PSPDFSizeThumbnail];
        }else {
            backgroundImage = [[PSPDFCache sharedPSPDFCache] imageForDocument:document page:page size:PSPDFSizeThumbnail];
            
            if (!backgroundImage) { 
                // decompresses image in background
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    UIImage *cachedImage = nil;
                    if(self.window && !destroyed_) {
                        cachedImage = [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:document page:page size:PSPDFSizeThumbnail preload:YES];
                    }
                    // *always* call back main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // only update image if the big image is not yet loaded
                        if (cachedImage && self.window && !destroyed_ && (!self.backgroundImageView.image || self.backgroundImageView.image.size.width < cachedImage.size.width)) {
                            [self setBackgroundImage:cachedImage animated:YES];
                        }
                    });
                });
            }
        }
    }else {
        PSPDFLogVerbose(@"Full page cache hit for %d", page);
    }
    
    [self setBackgroundImage:backgroundImage animated:NO];
    
    // start caching document after two seconds
    [self performSelector:@selector(startCachingDocument) withObject:nil afterDelay:2.0];
    
    // add delay for annotation loading; improve scrolling speed (but reload instantly if already there)
    if ([annotationViews_ count] > 0) {
        [self loadPageAnnotations];
    }else {
        [self performSelector:@selector(loadPageAnnotations) withObject:nil afterDelay:kPSPDFInitialAnnotationLoadDelay];
    }
}

- (void)setBackgroundImage:(UIImage *)image animated:(BOOL)animated {
    if (self.backgroundImageView.image != image) {
        if (animated && kPSPDFKitPDFAnimationDuration > 0.f) {
            CATransition *transition = [CATransition animation];
            transition.duration = kPSPDFKitPDFAnimationDuration;
            transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            transition.type = kCATransitionFade;
            [self.backgroundImageView.layer addAnimation:transition forKey:@"image"];
        }
        
        self.backgroundImageView.image = image;
    }
    self.backgroundImageView.backgroundColor = image ? [UIColor clearColor] : [self.document backgroundColorForPage:self.page];
    
    //CGRect rectInWindow = [self.backgroundImageView convertRect:self.backgroundImageView.frame toView:self.backgroundImageView.window];
    
    // if image is readonably close to target size, don't scale it (fixes blurry text)
    /*
     BOOL isFullSize = NO;    
     if (image) {
     int widthDiff = abs(self.backgroundImageView.frame.size.width - image.size.width);
     int heightDiff = abs(self.backgroundImageView.frame.size.height - image.size.height);        
     isFullSize = widthDiff < 2 && heightDiff < 2;
     }*/
    
    //if(isFullSize) {
    //    backgroundImageView_.contentMode = UIViewContentModeTopLeft; // doesn't stretch image
    //}else {
    backgroundImageView_.contentMode = UIViewContentModeScaleToFill;
    //}
}

- (void)destroyPageAndRemoveFromView:(BOOL)removeFromView callDelegate:(BOOL)callDelegate {
    // try calling delegate
    // TODO: move this somewhere else?
    // TODO: ARC-RELATED bug. If this is called within pdfController dealloc, we get an weird over-release
    if (callDelegate && self.document) {
        if (![NSThread isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.scrollView.pdfController delegateWillUnloadPageView:self];
            });
        }else {
            [self.scrollView.pdfController delegateWillUnloadPageView:self];
        }
    }
    
    self.destroyed = YES;
    if (removeFromView) {
        NSAssert([NSThread isMainThread], @"Must run on main thread");
        [self.pdfView stopTiledRenderingAndRemoveFromSuperlayer];
        [self removeFromSuperview];
    }
}

// needs to be called while view is still visible, and only in main
- (void)setDestroyed:(BOOL)destroyed {
    if (destroyed_ != destroyed) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startCachingDocument) object:nil];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadPageAnnotations) object:nil];
        destroyed_ = destroyed;
    }
}

- (void)setHidden:(BOOL)hidden {
    if (hidden != self.hidden) {
        [super setHidden:hidden];
        [self callAnnotationVisibleDelegateToShow:!hidden];
    }    
}

// detects when the controller/view goes offscreen - pause videos etc
- (void)willMoveToWindow:(UIWindow *)newWindow {
    PSPDFLogVerbose(@"new window for page: %@", newWindow);
    // inform annotations
    if(self.document) {
        [self callAnnotationVisibleDelegateToShow:newWindow != nil];
    }
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    
    // inform annotations that the parent size has changed
    for (UIView *subview in self.subviews) {
        if ([subview conformsToProtocol:@protocol(PSPDFAnnotationView)]) {
            if ([subview respondsToSelector:@selector(didChangePageFrame:)]) {
                [(id<PSPDFAnnotationView>)subview didChangePageFrame:self.frame];
            }
        }
    }
}

- (void)updateShadow {
    if (self.isShadowEnabled) {
        // TODO: make one library for shadow services (see PSPDFScrollView)
        CALayer *backgroundLayer = self.layer;
        backgroundLayer.shadowColor = [UIColor blackColor].CGColor;
        backgroundLayer.shadowOffset = PSIsIpad() ? CGSizeMake(10.0f, 10.0f) : CGSizeMake(8.0f, 8.0f); 
        backgroundLayer.shadowRadius = 4.0f;
        backgroundLayer.masksToBounds = NO;
        CGSize size = self.bounds.size; 
        CGFloat moveShadow = -12;
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(moveShadow, moveShadow, size.width+fabs(moveShadow/2), size.height+fabs(moveShadow/2))];
        backgroundLayer.shadowOpacity = shadowOpacity_;
        backgroundLayer.shadowPath = path.CGPath;
        
        if (updateShadowBlock_) {
            updateShadowBlock_(self);
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateShadow];
}

@end
