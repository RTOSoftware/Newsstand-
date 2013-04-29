//
//  PSPDFPageViewController.m
//  PSPDFKit
//
//  Created by Peter Steinberger on 10/17/11.
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFPageViewController.h"
#import "PSPDFViewController.h"
#import "PSPDFDocument.h"
#import "PSPDFSinglePageViewController.h"
#import "PSPDFPageView.h"
#import "PSPDFTilingView.h"
#import "PSPDFAnnotationView.h"
#import "PSPDFPagedScrollView.h"
#import "PSPDFViewController+Internal.h"
#import <objc/runtime.h>
#import "PSPDFPatches.h"

@implementation PSPDFPageViewController

@synthesize useSolidBackground = useSolidBackground_;
@synthesize pdfController = pdfController_;
@synthesize scrollView = scrollView_;
@synthesize page = page_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - private

// returns the singlePageController, looks if it may already be created
- (PSPDFSinglePageViewController *)singlePageControllerForPage:(NSUInteger)page {
    PSPDFSinglePageViewController *singlePage = nil;
    
    for (PSPDFSinglePageViewController *currentSinglePage in self.viewControllers) {
        if (currentSinglePage.page == page) {
            singlePage = currentSinglePage; break;
        }
    }
    
    if (!singlePage) {
        singlePage = [[PSPDFSinglePageViewController alloc] initWithPDFController:self.pdfController page:page];
    }
    
    singlePage.useSolidBackground = useSolidBackground_;
    return singlePage;
}

// helper to correctly pre-setup view controllers
- (void)setupViewControllersDoublePaged:(BOOL)doublePaged animated:(BOOL)animated direction:(UIPageViewControllerNavigationDirection)direction {
    NSArray *viewControllers;
    PSPDFLogVerbose(@"setupViewControllersDoublePaged:%d animated:%d direction:%d", doublePaged, animated, direction);
    if (doublePaged) {
        NSUInteger basePage = self.page;
        PSPDFSinglePageViewController *leftPage = [self singlePageControllerForPage:basePage];
        PSPDFSinglePageViewController *rightPage = [self singlePageControllerForPage:basePage+1];
        viewControllers = [NSArray arrayWithObjects:leftPage, rightPage, nil];
    }else {
        PSPDFSinglePageViewController *singlePage = [self singlePageControllerForPage:self.page];
        viewControllers = [NSArray arrayWithObject:singlePage];
    }
    
    // perform sanity check if something changed at all
    BOOL changed = ![viewControllers isEqualToArray:self.viewControllers];
    if (changed) {
        [self setViewControllers:viewControllers direction:direction animated:animated completion:nil];
    }    
}

- (NSUInteger)fixPageNumberForDoublePageMode:(NSUInteger)page forceDualPageMode:(BOOL)forceDualPageMode {
    // ensure that we've not set the wrong page for double page mode
    NSUInteger correctedPage = page;
    if (([self.pdfController isDualPageMode] || forceDualPageMode) && [self.pdfController isRightPageInDoublePageMode:correctedPage]) {
        correctedPage--;
    }
    return correctedPage;
}

// adapt the frame so that the page doesn't "bleed out". 
- (void)updateViewSize {
    CGSize size = CGSizeZero;
    
    for (PSPDFSinglePageViewController *pageController in self.viewControllers) {
        PSPDFSinglePageViewController *currentPageController = pageController;
        
        // if we're at first/last page and in two page mode, just copy the size of the other page
        if (currentPageController.page == NSUIntegerMax || currentPageController.page >= [[pdfController_ document] pageCount]) {
            if ([self.viewControllers indexOfObject:pageController] == 0) {
                currentPageController = (PSPDFSinglePageViewController *)[self.viewControllers lastObject];
            }else {
                currentPageController = (PSPDFSinglePageViewController *)[self.viewControllers objectAtIndex:0];
            }
        }
        CGSize pageViewSize = currentPageController.pageView.frame.size;
        
        // we may need to wait for viewWillLayoutSubviews to re-set the pageView frame after a rotation 
        // this can happen because pageView_ auto-resizes and may set height to zero,
        // and due to a timing issue on updateViewSize we mess up our view size if we don't break here.
        if ((pageViewSize.width == 0 || pageViewSize.height == 0) && pageViewSize.width + pageViewSize.height > 0) {
            return;
        }
        
        size = CGSizeMake(size.width + pageViewSize.width, MAX(size.height, pageViewSize.height)); 
    }
    
    // the system automatically centers the view for us - no need to do extra work!
    CGRect newFrame = CGRectMake(0, 0, size.width, size.height);
    PSPDFLogVerbose(@"old frame: %@ ---- new frame: %@", NSStringFromCGRect(self.view.frame), NSStringFromCGRect(newFrame));
    self.view.frame = newFrame;
    [self.view.superview setNeedsLayout];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithPDFController:(PSPDFViewController *)pdfController {
    BOOL isDoublePaged = [pdfController isDualPageMode];
    
    // Note: Not using the constant UIPageViewControllerOptionSpineLocationKey, we would need to weak-link UIKit for that.
    NSDictionary *optionDict = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:isDoublePaged ? UIPageViewControllerSpineLocationMid : UIPageViewControllerSpineLocationNone] forKey:@"UIPageViewControllerOptionSpineLocationKey"];
    
    if (self = [super initWithTransitionStyle:UIPageViewControllerTransitionStylePageCurl navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:optionDict]) {
        PSPDFRegisterObject(self);
        pdfController_ = pdfController;
        page_ = pdfController.page;
        self.delegate = self;
        self.dataSource = self;
        
        [self setupViewControllersDoublePaged:[self.pdfController isDualPageMode] animated:NO direction:UIPageViewControllerNavigationDirectionForward];        
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);   
    self.pdfController = nil;
    self.delegate = nil;
    self.dataSource = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIViewController

// later becomes - (BOOL)pspdf_customPointInside:(CGPoint)point withEvent:(UIEvent *)event on _UIPageViewControllerContentView.
BOOL pspdf_customPointInside(id this, SEL this_cmd, CGPoint point, UIEvent *event);
BOOL pspdf_customPointInside(id this, SEL this_cmd, CGPoint point, UIEvent *event) {
    CGPoint tranlatedPoint = [this convertPoint:point toView:[this superview]];
    BOOL isPointInSuperView = [[this superview] pointInside:tranlatedPoint withEvent:event];
    return isPointInSuperView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // hack into _UIPageViewControllerContentView to allow gestures to fire even if not in the view. All w/o private API!
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class pageCurlViewClass = [self.view class]; // _UIPageViewControllerContentView
        if (pageCurlViewClass) {
            SEL customPointInside = NSSelectorFromString(@"pspdf_customPointInside:withEvent:");
            const char *typeEncoding = method_getTypeEncoding(class_getInstanceMethod([UIView class], @selector(pointInside:withEvent:)));
            class_addMethod(pageCurlViewClass, customPointInside, (IMP)pspdf_customPointInside, typeEncoding);
            pspdf_swizzle(pageCurlViewClass, @selector(pointInside:withEvent:), customPointInside);
        }
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // do very late in the game, after all transforms have been applied
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateViewSize];
    });
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    // restore original frame before we animate.
    self.view.frame = self.view.superview.frame;
    
    // remove any MPMoviePlayerControllers as they mess with the rotation animation and get recreated anyway
    // TODO: report another bug for UIPageViewController...
    for(PSPDFSinglePageViewController *singlePage in self.viewControllers) {
        for (UIView *view in singlePage.pageView.subviews) {
            if ([view conformsToProtocol:@protocol(PSPDFAnnotationView)]) {
                [view removeFromSuperview];
            }
        }
    }
    
    // kill all CATiledLayers so they don't redraw while we animate.
    // we will regenerate the whole page anyway so we can optimize rotation here.
    for(PSPDFSinglePageViewController *singlePage in self.viewControllers) {
        [singlePage.pageView.pdfView stopTiledRenderingAndRemoveFromSuperlayer];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setPdfController:(PSPDFViewController *)pdfController {
    pdfController_ = pdfController;
    
    for (PSPDFSinglePageViewController *singlePageController in self.viewControllers) {
        singlePageController.pdfController = pdfController;
    }
    
    // ensure we find _all_ controllers, even if UIPageViewController messes up.
    for (UIViewController *viewController in self.childViewControllers) {
        if ([viewController isKindOfClass:[PSPDFSinglePageViewController class]]) {
            [(PSPDFSinglePageViewController *)viewController setPdfController:nil];
        }
    }
}

- (void)setPage:(NSUInteger)page {
    [self setPage:page animated:NO];
}

- (void)setPage:(NSUInteger)page animated:(BOOL)animated {
    // ensure that we've not set the wrong page for double page mode
    NSUInteger correctedPage = [self fixPageNumberForDoublePageMode:page forceDualPageMode:NO];
    if (page_ != correctedPage) {
        BOOL forwardAnimation = (NSInteger)correctedPage > (NSInteger)page_ && correctedPage != NSUIntegerMax;
        page_ = correctedPage;
        [self setupViewControllersDoublePaged:[self.pdfController isDualPageMode] animated:animated direction:forwardAnimation ? UIPageViewControllerNavigationDirectionForward : UIPageViewControllerNavigationDirectionReverse];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIPageViewControllerDataSource

// In terms of navigation direction. For example, for 'UIPageViewControllerNavigationOrientationHorizontal', view controllers coming 'before' would be to the left of the argument view controller, those coming 'after' would be to the right.
// Return 'nil' to indicate that no more progress can be made in the given direction.
// For gesture-initiated transitions, the page view controller obtains view controllers via these methods, so use of setViewControllers:direction:animated:completion: is not required.
- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController {
    PSPDFSinglePageViewController *previousPageController = (PSPDFSinglePageViewController *)viewController;
    PSPDFLogVerbose(@"viewControllerBeforeViewController:%d", previousPageController.page);
    
    // block if scrolling is not enabled
    if (!pdfController_.scrollingEnabled) {
        return nil;
    }
    
    // allow special case for a document open (where the leftPage is empty)
    BOOL allowEmptyFirstPage = pdfController_.isDualPageMode && previousPageController.page == 0 && !pdfController_.doublePageModeOnFirstPage;
    if ((previousPageController.page == 0 || previousPageController.page >= self.pdfController.document.pageCount) && !allowEmptyFirstPage) {
        return nil;
    }
    
    // hide UI
    [pdfController_ hideControls];
    
    NSUInteger newPage = previousPageController.page-1;
    PSPDFSinglePageViewController *singlePageController = [[PSPDFSinglePageViewController alloc] initWithPDFController:self.pdfController
                                                                                                                  page:newPage];    
    singlePageController.useSolidBackground = useSolidBackground_;
    return singlePageController;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController {
    PSPDFSinglePageViewController *nextPageController = (PSPDFSinglePageViewController *)viewController;
    PSPDFLogVerbose(@"viewControllerAfterViewController:%d", nextPageController.page);
    
    // block if scrolling is not enabled
    if (!pdfController_.scrollingEnabled) {
        return nil;
    }
    
    BOOL allowEmptyLastPage = pdfController_.isDualPageMode && nextPageController.page == self.pdfController.document.pageCount-1 && ![self.pdfController isRightPageInDoublePageMode:nextPageController.page];
    BOOL allowNegativeIncrement = nextPageController.page == NSUIntegerMax;
    if (nextPageController.page >= self.pdfController.document.pageCount-1 && !allowEmptyLastPage && !allowNegativeIncrement) {
        return nil;
    }
    
    // hide UI
    [pdfController_ hideControls];
    
    NSUInteger newPage = nextPageController.page+1;
    PSPDFSinglePageViewController *singlePageController = [[PSPDFSinglePageViewController alloc] initWithPDFController:self.pdfController
                                                                                                                  page:newPage];
    singlePageController.useSolidBackground = useSolidBackground_;
    return singlePageController;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIPageViewControllerDelegate

// Sent when a gesture-initiated transition ends. The 'finished' parameter indicates whether the animation finished, while the 'completed' parameter indicates whether the transition completed or bailed out (if the user let go early).
- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed {
    PSPDFLogVerbose(@"finished animating:%d transitionCompleted:%d", finished, completed);
    
    // save new page and apply fixes for Apple's broken UIPageViewController.
    // (at least within iOS 5.0 - 5.1b3)
    if (completed) {
        if ([pageViewController.viewControllers count]) {
            
            // apply new page
            PSPDFSinglePageViewController *singlePageViewController = [pageViewController.viewControllers objectAtIndex:0];
            NSUInteger newPage = singlePageViewController.page;
            page_ = newPage == NSUIntegerMax ? 0 : newPage;
            self.pdfController.realPage = page_;
            
            // check all views and remove any leftover pages / animation stuff (WTF, Apple!?)
            for (UIView *subview in self.view.subviews) {
                BOOL containsPSPDFPageView = [subview.subviews count] == 1 && [[subview.subviews objectAtIndex:0] isKindOfClass:[PSPDFPageView class]];
                
                BOOL removeView = YES;
                if (containsPSPDFPageView) {
                    PSPDFPageView *pageView = [subview.subviews objectAtIndex:0];
                    
                    if (![pdfController_ isDualPageMode]) {
                        removeView = pageView.page != page_;
                    }else {
                        // search if one of the controllers matches the page, remove if not.
                        for (PSPDFSinglePageViewController *single in pageViewController.viewControllers) {
                            if(single.page == pageView.page) {
                                removeView = NO; break;
                            }
                        }
                    }                    
                }
                
                if (removeView) {
                    PSPDFLogVerbose(@"Fixed bug in UIPageViewController: remove leftover view %@", subview);
                    [subview removeFromSuperview];
                }
            }
            
            // next, check if there is a leftover controller
            for (UIViewController *childController in self.childViewControllers) {
                BOOL found = NO;
                for (PSPDFSinglePageViewController *singlePage in pageViewController.viewControllers) {
                    if(childController == singlePage) {
                        found = YES; break;
                    }
                }
                
                if (!found) {
                    PSPDFLogVerbose(@"Fixed bug in UIPageViewController: remove leftover controller %@", childController);
                    [childController removeFromParentViewController];
                    
                    // at this point, Apple internally called beginDisablingInterfaceAutorotation
                    // but never calls the corresponding endDisablingInterfaceAutorotation. (BUG!)
                    // (Both of them are, unfortunately, private API.)
                    
                    // So either we bite the Apple and fix it ourselves, or probably wait until iOS6 for
                    // UIPageViewController to be finally stable (And it's rarely used, so it's low priority).
                    
                    // If you're afraid about private API,
                    // set _PSPDFKIT_DONT_USE_OBFUSCATED_PRIVATE_API_ in your preprocessor defines.
                    
                    // Note however that Apple's checks are extremely limited,
                    // and a simple obfuscation like this usually is no problem at all.
                    // I do have and know several apps in the store that use the same technique.
                    #ifndef _PSPDFKIT_DONT_USE_OBFUSCATED_PRIVATE_API_
                    pspdf_endDisableIfcAutorotation(nil, nil);
                    #endif
                }                
            }
        }
    }
        
    // hide UI
    [pdfController_ hideControls];
    
    // adapt view size in next runloop (or we get in UIKit-trouble)
    if (finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateViewSize];
        });
    }
}

// Delegate may specify a different spine location for after the interface orientation change. Only sent for transition style 'UIPageViewControllerTransitionStylePageCurl'.
// Delegate may set new view controllers or update double-sided state within this method's implementation as well.
- (UIPageViewControllerSpineLocation)pageViewController:(UIPageViewController *)pageViewController spineLocationForInterfaceOrientation:(UIInterfaceOrientation)orientation {
    
    // ensure we have the correct page for dual page mode
    BOOL isDualPageMode = [self.pdfController isDualPageModeForOrientation:orientation];
    UIPageViewControllerSpineLocation spineLocation = UIPageViewControllerSpineLocationNone;
    if (isDualPageMode) {
        page_ = [self fixPageNumberForDoublePageMode:self.pdfController.realPage forceDualPageMode:YES];
        spineLocation = UIPageViewControllerSpineLocationMid;
        [self setupViewControllersDoublePaged:YES animated:YES direction:UIPageViewControllerNavigationDirectionForward];
    }else {
        page_ = self.pdfController.realPage;
        [self setupViewControllersDoublePaged:NO animated:YES direction:UIPageViewControllerNavigationDirectionForward];
    }
    
    return spineLocation;
}

// Undocumented that this class is the gesture recognizer delegate, but pretty obvious.
// Confirmation: https://github.com/steipete/iOS-Runtime-Headers/blob/master/Frameworks/UIKit.framework/UIPageViewController.h
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // disable any paging while we're in zoom mode
    BOOL isNotZoomed = self.scrollView.zoomScale == 1;
    return isNotZoomed;
}

@end
