//
//  PSPDFViewController.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFTransparentToolbar.h"
#import "PSPDFThumbnailGridViewCell.h"
#import "PSPDFOutlineViewController.h"
#import "PSPDFPageViewController.h"
#import "PSPDFPagedScrollView.h"
#import "PSPDFViewController+Internal.h"
#import "PSPDFViewControllerDelegate.h"
#import "PSPDFGridView.h"
#import "PSPDFWebViewController.h"
#import "PSPDFIconGenerator.h"
#import <QuartzCore/QuartzCore.h>
#import <MessageUI/MessageUI.h>

#define kDismissActivePopover @"kDismissActivePopover"
#define kPSPDFViewControllerFrameChanged @"kPSPDFViewControllerFrameChanged"

@interface PSPDFViewController() <UIDocumentInteractionControllerDelegate, MFMailComposeViewControllerDelegate, PSPDFGridViewActionDelegate, PSPDFGridViewDataSource> {
    UIDocumentInteractionController *documentInteractionController_;
    BOOL pageCurlEnabled_;
    UIInterfaceOrientation lastOrientation_;
    UISegmentedControl *viewModeSegment_;
    __ps_weak UINavigationController *navigationController_;
    UIBarStyle previousBarStyle_;
    BOOL previousBarStyleTranslucent_;
    CGFloat lastContentOffset_;
    NSInteger targetPageAfterRotate_;
    NSUInteger lastPage_;
    BOOL _isShowingOpenInMenu;
    BOOL _isAnimatingPrint;
    BOOL _isShowingPrint;
    BOOL _isReloading;
    BOOL documentRectCacheLoaded_;
    BOOL rotationActive_;
    BOOL rotationAnimationActive_;
    BOOL scrolledDown_;
    struct {
        unsigned int delegateWillDisplayDocument:1;
        unsigned int delegateDidDisplayDocument:1;
        unsigned int delegateDidShowPageView:1;
        unsigned int delegateDidRenderPageView:1;
        unsigned int delegateDidChangeViewMode:1;
        unsigned int delegateDidTapOnPageView:1;
        unsigned int delegateDidTapOnAnnotation:1;
        unsigned int delegateShouldDisplayAnnotation:1;
        unsigned int delegateViewForAnnotation:1;        
        unsigned int delegateAnnotationViewForAnnotation:1;
        unsigned int delegateWillShowAnnotationView:1;
        unsigned int delegateDidShowAnnotationView:1;
        unsigned int delegateDidLoadPageView:1;
        unsigned int delegateWillUnloadPageView:1;
    } delegateFlags_;
}

@property(nonatomic, strong) PSPDFGridView *gridView;
@property(nonatomic, strong) PSPDFHUDView *hudView;
@property(nonatomic, strong) PSPDFPositionView *positionView;
@property(nonatomic, assign, readonly, getter=isLandscape) BOOL landscape;
@property(nonatomic, assign, getter=isViewVisible) BOOL viewVisible;
@property(nonatomic, assign, getter=isNavigationBarHidden) BOOL navigationBarHidden;
@property(nonatomic, assign, getter=isRotationActive) BOOL rotationActive;
@property(nonatomic, assign) NSUInteger page;
@property(nonatomic, strong) UIBarButtonItem *closeButton;
@property(nonatomic, strong) UIToolbar *leftToolbar;
@property(nonatomic, strong) UIBarButtonItem *viewModeButton;
@property(nonatomic, strong) PSPDFScrobbleBar *scrobbleBar;
@property(nonatomic, strong) UIScrollView *pagingScrollView;
@property(nonatomic, strong) NSMutableSet *recycledPages;
@property(nonatomic, strong) NSMutableSet *visiblePages;
@property(nonatomic, assign) UIStatusBarStyle savedStatusBarStyle;
@property(nonatomic, assign) BOOL savedStatusBarVisibility;
@property(nonatomic, retain) PSPDFPageViewController *pageViewController;

/// snap pages into screen size. If disabled, you get one big scrollview (but zoom is resetted). Defaults to YES.
/// TODO: this doesn't work as supposed. Still work in progress.
@property(nonatomic, assign, getter=isPagingEnabled) BOOL pagingEnabled;

- (CGFloat)hudTransparencyOffset;
- (BOOL)isDarkHUD;
- (void)delegateDidChangeViewMode:(PSPDFViewMode)viewMode;
- (void)reloadDataAndScrollToPage:(NSUInteger)page;
- (void)destroyVisiblePages;
- (void)preloadNextThumbnails;
- (void)tilePages:(BOOL)forceUpdate;
- (void)hideControlsIfPageMode;
- (void)configurePage:(PSPDFScrollView *)page forIndex:(NSUInteger)index;
- (BOOL)isDisplayingPageForIndex:(NSUInteger)index;
- (CGRect)frameForPageAtIndex:(NSUInteger)index;
- (CGRect)frameForPageInScrollView;
@end

@interface PSPDFViewControllerView : UIView
@end

@implementation PSPDFViewController

@synthesize delegate = delegate_;
@synthesize document = document_;
@synthesize realPage = realPage_;
@synthesize gridView = gridView_;
@synthesize navigationBarHidden = navigationBarHidden_;
@synthesize viewMode = viewMode_;
@synthesize viewModeControlVisible = viewModeControlVisible_;
@synthesize pageMode = pageMode_;
@synthesize doublePageModeOnFirstPage = doublePageModeOnFirstPage_;
@synthesize landscape = landscape_;
@synthesize rotationActive = rotationActive_;
@synthesize closeButton = closeButton_;
@synthesize leftToolbar = leftToolbar_;
@synthesize viewModeButton = viewModeButton_;
@synthesize popoverController = popoverController_;
@synthesize backgroundColor = backgroundColor_;
@synthesize tintColor = tintColor_;
@synthesize scrobbleBar = scrobbleBar_;
@synthesize scrobbleBarEnabled = scrobbleBarEnabled_;
@synthesize positionViewEnabled = positionViewEnabled_;
@synthesize toolbarEnabled = toolbarEnabled_;
@synthesize scrollOnTapPageEndEnabled = scrollOnTapPageEndEnabled_;
@synthesize iPhoneThumbnailSizeReductionFactor = iPhoneThumbnailSizeReductionFactor_;
@synthesize pagingScrollView = pagingScrollView_;
@synthesize recycledPages = recycledPages_;
@synthesize visiblePages = visiblePages_;
@synthesize hudView = hudView_;
@synthesize positionView = positionView_;
@synthesize maximumZoomScale = maximumZoomScale_;
@synthesize pagePadding = pagePadding_;
@synthesize zoomingSmallDocumentsEnabled = zoomingSmallDocumentsEnabled_;
@synthesize shadowEnabled = shadowEnabled_;
@synthesize pageScrolling = pageScrolling_;
@synthesize fitWidth = fitWidth_;
@synthesize linkAction = linkAction_;
@synthesize printEnabled = printEnabled_;
@synthesize openInEnabled = openInEnabled_;
@synthesize thumbnailSize = thumbnailSize_;
@synthesize viewVisible = viewVisible_;
@synthesize pagingEnabled = pagingEnabled_;
@synthesize statusBarStyleSetting = statusBarStyleSetting_;
@synthesize savedStatusBarStyle = savedStatusBarStyle_;
@synthesize savedStatusBarVisibility = savedStatusBarVisibility_;
@synthesize preloadedPagesPerSide = preloadedPagesPerSide_;
@synthesize scrollingEnabled = scrollingEnabled_;
@synthesize overrideClassNames = overrideClassNames_;
@synthesize pageCurlEnabled = pageCurlEnabled_;
@synthesize pageViewController = pageViewController_;
@synthesize annotationAnimationDuration = annotationAnimationDuration_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Custom Class Helper

// Looks up an entry in overrideClassNames for custom Class subclasses
- (Class)classForClass:(Class)originalClass {
    Class overrideClassObject = nil;
    NSString *overriddenClassName = [overrideClassNames_ objectForKey:NSStringFromClass(originalClass)];
    if (overriddenClassName) {
        overrideClassObject = NSClassFromString(overriddenClassName);
        if (!overrideClassObject) {
            PSPDFLogError(@"Error! Couldn't find class %@ in runtime. Using default %@ instead.", overriddenClassName, NSStringFromClass(originalClass));
        }
    }
    return overrideClassObject ? overrideClassObject : originalClass;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Controls

// helper to detect if we're embedded or not.
- (BOOL)isEmbedded {
    if (!self.view.window) {
        return NO;
    }
    CGRect viewRect = self.view.bounds;
    viewRect = [self.view convertRect:viewRect toView:nil];// Convert to the window's coordinate space.
    CGRect appRect = [[UIScreen mainScreen] applicationFrame];
    // use a heuristic to compensate status bar effects (transparency, call notification, etc)
    BOOL isEmbedded = fabs(viewRect.size.width - appRect.size.width) > 40.f || fabs(viewRect.size.height - appRect.size.height) > 40.f;
    PSPDFLogVerbose(@"embedded: %d (%@:%@)", isEmbedded, NSStringFromCGRect(viewRect), NSStringFromCGRect(appRect));
    return isEmbedded;
}

- (void)setStatusBarStyle:(UIStatusBarStyle)statusBarStyle animated:(BOOL)animated {
    if (![self isEmbedded] && !(self.statusBarStyleSetting & PSPDFStatusBarIgnore)) {
        [[UIApplication sharedApplication] setStatusBarStyle:statusBarStyle animated:animated];
    }
}

- (void)setStatusBarHidden:(BOOL)hidden withAnimation:(UIStatusBarAnimation)animation {
    if (![self isEmbedded] && !(self.statusBarStyleSetting & PSPDFStatusBarIgnore)) {
        [[UIApplication sharedApplication] setStatusBarHidden:hidden withAnimation:animation];
    }
}

- (void)closeModalView {
    [self dismissModalViewControllerAnimated:YES];
}

- (void)presentModalViewController:(UIViewController *)controller withCloseButton:(BOOL)closeButton animated:(BOOL)animated {
    UINavigationController *navController = (UINavigationController *)controller;
    if (![controller isKindOfClass:[UINavigationController class]]) {
        navController = [[UINavigationController alloc] initWithRootViewController:controller];
    }else {
        controller = navController.topViewController;
    }
    
    // informal protocol
    if (closeButton) {
        if ([controller respondsToSelector:@selector(setShowCancel:)]) {
            [(PSPDFSearchViewController *)controller setShowCancel:YES];
            navController.navigationBarHidden = YES;
            
            // darken up the statusbar
            if ([UIApplication sharedApplication].statusBarStyle == UIStatusBarStyleBlackTranslucent) {
                [self setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:YES];
            }
        }else {
            controller.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:PSPDFLocalize(@"Close") style:UIBarButtonItemStyleBordered target:self action:@selector(closeModalView)];
        }
    }
    
    controller.navigationItem.title = self.document.title;
    BOOL hasTransparentStatusBar = [UIApplication sharedApplication].statusBarStyle == UIStatusBarStyleBlackTranslucent;
    [[self masterViewController] presentModalViewController:navController animated:animated];
    
    // darken up the statusbar
    if (hasTransparentStatusBar) {
        [self setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:animated];
    }    
}

- (void)documentButtonPressed {
    [self dismissModalViewControllerAnimated:YES];
}

- (void)showControls {
    if (self.isNavigationBarHidden) {
        [self setHUDVisible:YES animated:YES];
    }
}

- (void)hideControls {
    if (!self.isNavigationBarHidden && !self.popoverController) {
        [self setHUDVisible:NO animated:YES];
    }
}

- (void)toggleControls {
    BOOL newHUDVisibilityStatus = ![self isHUDVisible];
    if (viewModeSegment_.selectedSegmentIndex == PSPDFViewModeThumbnails || self.popoverController != nil) {
        newHUDVisibilityStatus = YES;
    }
    [self setHUDVisible:newHUDVisibilityStatus animated:YES];
}


// instantly resign search keyboard, don't wait until popover is gone
- (void)dismissKeyboardInSearchViewControllerPopover:(UIPopoverController *)popoverController {
    if ([popoverController.contentViewController isKindOfClass:[PSPDFSearchViewController class]]) {
        // lock current size (so that it doesn't change while animating out keyboard
        popoverController.contentViewController.contentSizeForViewInPopover = popoverController.contentViewController.view.frame.size;
        // instantly resign keyboard, don't wait for willDissapear which is sent AFTER complete popover animation
        [((PSPDFSearchViewController *)popoverController.contentViewController).searchBar resignFirstResponder];
    }
}

- (BOOL)checkAndDismissPrintPopoverAnimated:(BOOL)animated {
    BOOL dismissed = NO;
    if (_isShowingPrint || _isAnimatingPrint) {
        // stupid UIPrintInteractionController. We need to block calls during animation
        // else it crashes on us with a "dealloc reached while still visible" bla.
        if (!_isAnimatingPrint) {
            [[UIPrintInteractionController sharedPrintController] dismissAnimated:animated];
            _isAnimatingPrint = animated;
        }
        dismissed = YES;
    }
    return dismissed;
}

- (BOOL)checkAndDismissDocumentInteractionControllerAnimated:(BOOL)animated {
    BOOL dismissed = NO;
    if (documentInteractionController_) {
        [documentInteractionController_ dismissMenuAnimated:animated];
        dismissed = YES;
    }
    documentInteractionController_.delegate = nil;
    documentInteractionController_ = nil;
    return dismissed;
}

// check for specific view controller if given, or just try to hide
- (BOOL)checkAndDismissPopoverForViewControllerClass:(Class)viewControllerClass animated:(BOOL)animated {
    BOOL dismissed = NO;
    
    if (!viewControllerClass || viewControllerClass == [UIDocumentInteractionController class]) {
        dismissed = [self checkAndDismissDocumentInteractionControllerAnimated:NO];
    }
    if (!viewControllerClass || viewControllerClass == [UIPrintInteractionController class]) {
        dismissed = [self checkAndDismissPrintPopoverAnimated:NO];
    }
    if ((viewControllerClass && [self.popoverController.contentViewController isKindOfClass:viewControllerClass]) || (!viewControllerClass && self.popoverController)) {
        [self dismissKeyboardInSearchViewControllerPopover:self.popoverController];
        [self.popoverController dismissPopoverAnimated:animated];
        self.popoverController = nil;
        dismissed = YES;
    }
    return dismissed;
}

// present controller modally or in popover - depending on the platform
- (void)presentModalOrInPopover:(UIViewController *)viewController sender:(id)sender  {
    // do we need to dismiss a popover?
    [self checkAndDismissPrintPopoverAnimated:NO];
    [self checkAndDismissDocumentInteractionControllerAnimated:NO];
    if ([self checkAndDismissPopoverForViewControllerClass:[viewController class] animated:YES]) {
        return;
    }
    
    if(PSIsIpad()) {
        UIPopoverController *popoverController = [[UIPopoverController alloc] initWithContentViewController:viewController];
        popoverController.passthroughViews = [NSArray arrayWithObject:self.navigationController.navigationBar];
        self.popoverController = popoverController; // remember controller
        [popoverController presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    }else {
        [self presentModalViewController:viewController withCloseButton:YES animated:YES];
    }    
}

// we only use that to add a passthroughViews. Hacky, but not critical if it fails.
- (UIPopoverController *)findPopoverControllerForController:(id)controller {
    UIPopoverController *popoverController = nil;
    
#ifndef PSPDFKIT_DONT_USE_OBFUSCATED_PRIVATE_API
    NSString *printInteractionControllerKeyPath = [NSString stringWithFormat:@"%@%@.%1$@%@%@%@.%@%5$@", @"print", @"State", @"Panel", @"View", @"Controller", @"pover"];
    @try {
        if ([controller isKindOfClass:[UIPrintInteractionController class]]) {
            popoverController = [controller valueForKeyPath:printInteractionControllerKeyPath];
        }else if ([controller isKindOfClass:[UIDocumentInteractionController class]]) {
            popoverController = [controller performSelector:@selector(popoverController)];
        }
        if (![popoverController isKindOfClass:[UIPopoverController class]]) { // failsafe checks
            popoverController = nil;
        }
    }
    @catch (NSException *exception) {
        @try {
            // If Apple fixes the typo in UIPrintPanelViewController and renames the _poverController ivar into _popoverController
            printInteractionControllerKeyPath = [printInteractionControllerKeyPath stringByReplacingOccurrencesOfString:@"pover" withString:@"popover"];
            popoverController = [controller valueForKeyPath:printInteractionControllerKeyPath];
        }
        @catch (NSException *exception) {
            popoverController = nil;
        }
    }
#endif
    
    return popoverController;
}

- (void)printAction:(id)sender {
    // do we need to dismiss a popover?
    if ([self checkAndDismissPrintPopoverAnimated:YES]) {
        return;
    }
    [self checkAndDismissPopoverForViewControllerClass:nil animated:NO];
    
    UIPrintInteractionController *printController = [UIPrintInteractionController sharedPrintController];
    
    if (self.document.data) {
        printController.printingItem = self.document.data;
    }else {
        printController.printingItems = [self.document filesWithBasePath];
    }
    printController.showsPageRange = YES;
    
    UIPrintInteractionCompletionHandler completionHandler = ^(UIPrintInteractionController *printInteractionController, BOOL completed, NSError *error) {
        _isShowingPrint = NO;
        _isAnimatingPrint = NO;
        PSPDFLogVerbose(@"printing finished: %d", completed);
        if (error) {
            PSPDFLogError(@"Could not print document. %@", error);
        }
    };
    if (PSIsIpad()) {
        [printController presentFromBarButtonItem:sender animated:YES completionHandler:completionHandler];
        
        // hacky way to add passthroughViews to the hidden print popover.
        dispatch_async(dispatch_get_main_queue(), ^{
            UIPopoverController *printPopover = [self findPopoverControllerForController:printController];
            printPopover.passthroughViews = [NSArray arrayWithObject:self.navigationController.navigationBar];
        });
    }else {
        [printController presentAnimated:YES completionHandler:completionHandler];
    }
    _isShowingPrint = YES;
}

- (void)openInAction:(id)sender {
    // do we need to dismiss a popover?
    if ([self checkAndDismissPopoverForViewControllerClass:[UIDocumentInteractionController class] animated:YES]) {
        return;
    }
    [self checkAndDismissPopoverForViewControllerClass:nil animated:NO];
    
    if (self.document.fileUrl) {
        _isShowingOpenInMenu = NO;
        documentInteractionController_ = [UIDocumentInteractionController interactionControllerWithURL:self.document.fileUrl];
        documentInteractionController_.delegate = self;
        [documentInteractionController_ presentOptionsMenuFromBarButtonItem:sender animated:YES];
        
        // hacky way to add passthroughViews to the hidden open in popover.
        if (PSIsIpad()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIPopoverController *printPopover = [self findPopoverControllerForController:documentInteractionController_];
                printPopover.passthroughViews = [NSArray arrayWithObject:self.navigationController.navigationBar];
            });
        }
    }
}

- (void)documentInteractionControllerDidDismissOpenInMenu:(UIDocumentInteractionController *)controller {
    documentInteractionController_.delegate = nil;
    documentInteractionController_ = nil;
    _isShowingOpenInMenu = NO;
}

- (void)documentInteractionControllerWillPresentOpenInMenu:(UIDocumentInteractionController *)controller {
    _isShowingOpenInMenu = YES;
}

- (void)documentInteractionControllerDidDismissOptionsMenu:(UIDocumentInteractionController *)controller {
    // we need to delay this check because this is called before WillPresentOpenInMenu.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_isShowingOpenInMenu) {
            documentInteractionController_.delegate = nil;
            documentInteractionController_ = nil;    
        }
    });
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller didEndSendingToApplication:(NSString *)application {
    PSPDFLogVerbose(@"Sent document to application: %@", application);
    documentInteractionController_.delegate = nil;
    documentInteractionController_ = nil;
    _isShowingOpenInMenu = NO;
}

- (void)searchAction:(id)sender {
    PSPDFSearchViewController *searchController = [[[self classForClass:[PSPDFSearchViewController class]] alloc] initWithDocument:self.document pdfController:self];
    [self presentModalOrInPopover:searchController sender:sender];
}

- (void)outlineAction:(id)sender {
    PSPDFOutlineViewController *outlineController = [[[self classForClass:[PSPDFOutlineViewController class]] alloc] initWithDocument:self.document pdfController:self];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:outlineController];
    [self presentModalOrInPopover:navController sender:sender];
}

- (UIStatusBarStyle)statusBarStyle {
    UIStatusBarStyle statusBarStyle;
    switch (self.statusBarStyleSetting & ~PSPDFStatusBarIgnore) {
        case PSPDFStatusBarSmartBlack:
            statusBarStyle = PSIsIpad() ? UIStatusBarStyleBlackOpaque : UIStatusBarStyleBlackTranslucent;
            break;
        case PSPDFStatusBarBlackOpaque:
            statusBarStyle = UIStatusBarStyleBlackOpaque;
            break;
        case PSPDFStatusBarDefaultWhite:
            statusBarStyle = UIStatusBarStyleDefault;
            break;
        case PSPDFStatusBarDisable:
        case PSPDFStatusBarInherit:
        default:
            statusBarStyle = [UIApplication sharedApplication].statusBarStyle;
            break;
    }
    
    return statusBarStyle;
}

- (BOOL)isHUDVisible {
    BOOL isHUDVisible = self.hudView.alpha > 0.f;
    return isHUDVisible;
}

// send all HUD subviews hidden/visible state
- (void)setHUDSubviewsHidden:(BOOL)hidden {
    for (UIView *hudSubView in self.hudView.subviews) {
        hudSubView.hidden = hidden;
    }
}

- (void)setHUDVisible:(BOOL)HUDVisible {
    [self setHUDVisible:HUDVisible animated:NO];
}

- (void)setHUDVisible:(BOOL)show animated:(BOOL)animated {
    [self willChangeValueForKey:@"HUDVisible"];
    BOOL isShown = [self isHUDVisible];
    UIStatusBarStyle statusBarStyle = [self statusBarStyle];
    if (show == isShown) {        
        if (self.isToolbarEnabled && statusBarStyle != UIStatusBarStyleDefault) {
            [self.navigationController setNavigationBarHidden:!isShown animated:YES];
        }
        [self didChangeValueForKey:@"HUDVisible"];
        return;
    }
    
    if (!PSIsIpad()) {
        [self setStatusBarStyle:statusBarStyle animated:YES];
        
        if (self.wantsFullScreenLayout && !(self.statusBarStyleSetting & PSPDFStatusBarDisable)) {
            [self setStatusBarHidden:!show withAnimation:UIStatusBarAnimationFade];
        }
    }
    
    self.navigationBarHidden = !show;
    
    // we need to perform this AFTER changing the statusbar, or else it gets overlayed (iOS BUG)
    dispatch_async(dispatch_get_main_queue(), ^{
        // only switch if we start showing
        if (!isShown && self.isToolbarEnabled) {
            self.navigationController.navigationBarHidden = YES;
            self.navigationController.navigationBarHidden = NO;    
        }
        
        PSPDFBasicBlock animationBlock = ^{
            self.hudView.alpha = show ? 1.f : 0.f;
            if (self.isToolbarEnabled && statusBarStyle != UIStatusBarStyleDefault && self.document.isValid) {
                self.navigationController.navigationBar.alpha = show ? 1.0f : 0.0f;
            }
        };
        
        if (animated) {
            CGFloat animationDuration = PSIsIpad() ? UINavigationControllerHideShowBarDuration : 0.4f;
            [UIView animateWithDuration:animationDuration delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
                [self setHUDSubviewsHidden:NO];
                animationBlock();
            } completion:^(BOOL finished) {
                if (finished) {
                    [self setHUDSubviewsHidden:!show];
                }
            }];
        }else {
            animationBlock();
            [self setHUDSubviewsHidden:!show];
        }
    });
    [self didChangeValueForKey:@"HUDVisible"];
}

- (void)viewModeSegmentChanged:(id)sender {
    UISegmentedControl *viewMode = (UISegmentedControl *)sender;
    NSUInteger selectedSegment = viewMode.selectedSegmentIndex;
    PSPDFLog(@"selected segment index: %d", selectedSegment);    
    [self setViewMode:selectedSegment == 0 ? PSPDFViewModeDocument : PSPDFViewModeThumbnails animated:YES];
}

// returns the current active content view
- (UIView *)contentView {
    return self.pagingScrollView;
}

- (void)setViewMode:(PSPDFViewMode)viewMode animated:(BOOL)animated {
    if (viewMode != viewMode_) {
        // ensure any popovers are hidden at that point
        [self checkAndDismissPopoverForViewControllerClass:nil animated:animated];
        
        if (animated) {
            [self willChangeValueForKey:@"viewModeAnimated"];
        }
        [self willChangeValueForKey:@"viewMode"];
        viewMode_ = viewMode;
        
        // sync thumbnail control
        if (viewModeSegment_.selectedSegmentIndex != viewMode) {
            viewModeSegment_.selectedSegmentIndex = viewMode;
        }
        
        // preparations (insert grid in view stack
        if(viewMode == PSPDFViewModeThumbnails) {
            self.gridView.hidden = NO;
            
            [self.gridView reloadData];
            [self.gridView scrollToObjectAtIndex:self.realPage atScrollPosition:PSPDFGridViewScrollPositionTop animated:NO];
            
            // honor top contentInset, but only when the item is on top
            if (self.gridView.contentOffset.y + self.gridView.frame.size.height <= self.gridView.contentSize.height) {
                CGPoint newContentOffset = CGPointMake(self.gridView.contentOffset.x, MAX(0, self.gridView.contentOffset.y - self.gridView.minEdgeInsets.top));
                [self.gridView setContentOffset:newContentOffset];
            }
            
            self.gridView.alpha = 0.0f;
            self.contentView.alpha = 1.0f;
        }else {
            [self.gridView setContentOffset:self.gridView.contentOffset animated:NO]; // stop scrolling, fixes a disappearing grid bug.
            self.gridView.alpha = 1.f;
            // TODO: screen gets black if we don't reload here. Should be fixed.
            [self reloadData];
            self.contentView.hidden = NO;
            self.pagingScrollView.alpha = 0.f;
        }
        
        [self.view insertSubview:self.contentView belowSubview:self.hudView];
        
        [UIView animateWithDuration:animated ? 0.25f : 0.f delay:0.f options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            if(viewMode == PSPDFViewModeThumbnails) { // grid            
                self.contentView.alpha = 0.f;
                self.gridView.alpha = 1.f;
            }else {
                self.contentView.alpha = 1.f;
                self.gridView.alpha = 0.f;
            }      
        } completion:^(BOOL finished) {
            if (finished) {
                if(viewMode == PSPDFViewModeThumbnails) {
                    self.contentView.hidden = YES;
                    [self destroyVisiblePages];
                }else {
                    self.gridView.hidden = YES;
                }      
            }
        }];
        if (animated) {
            [self didChangeValueForKey:@"viewModeAnimated"];
        }
        [self didChangeValueForKey:@"viewMode"];
        [self delegateDidChangeViewMode:viewMode];
    }
}

- (void)setViewMode:(PSPDFViewMode)viewMode {
    [self setViewMode:viewMode animated:NO];
}

- (void)updateGridForOrientation {
    gridView_.itemSpacing = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation) ? 28 : 15;
    
    // on iPhone, the navigation toolbar is either 44 (portrait) or 30 (landscape) pixels
    CGFloat transparentToolbarOffset = [self hudTransparencyOffset];
    NSUInteger spacing = 15;
    gridView_.minEdgeInsets = UIEdgeInsetsMake(spacing + transparentToolbarOffset, spacing, spacing, spacing);
}

- (PSPDFGridView *)gridView {
    if (!gridView_) {
        self.gridView = [[[self classForClass:[PSPDFGridView class]] alloc] initWithFrame:self.view.bounds];
        self.gridView.backgroundColor = [UIColor clearColor];
        self.gridView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.gridView.actionDelegate = self;
        self.gridView.style = PSPDFGridViewStyleSwap;
        self.gridView.centerGrid = YES;
        self.gridView.mainSuperView = self.view;
        [self updateGridForOrientation];
        self.gridView.dataSource = self;
        [self.view insertSubview:self.gridView belowSubview:self.hudView];
    }
    
    return gridView_;
}

- (BOOL)isDualPageModeForOrientation:(UIInterfaceOrientation)interfaceOrientation {
    BOOL isDualPageMode = self.pageMode == PSPDFPageModeDouble || (self.pageMode == PSPDFPageModeAutomatic && UIInterfaceOrientationIsLandscape(interfaceOrientation));
    if (isDualPageMode && self.pageMode == PSPDFPageModeAutomatic) {
        if (self.document.isValid) {
            PSPDFPageInfo *pageInfo = [self.document pageInfoForPage:0];
            if (pageInfo) {
                CGSize pageSize = pageInfo.pageRect.size;
                isDualPageMode = pageSize.height > pageSize.width && document_.pageCount > 1;
            }else {
                PSPDFLogWarning(@"Could not get pageInfo for %d", self.realPage);
            }
        }
    }
    return isDualPageMode;
}

// dynamically determine if we're landscape or not. (also checks if dual page mode makes any sense at all)
- (BOOL)isDualPageMode {
    return [self isDualPageModeForOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
}

/// YES if we are at the last page
- (BOOL)isLastPage {
    BOOL isLastPage = self.page >= self.document.pageCount-1;
    return isLastPage;
}

/// YES if we are at the first page
- (BOOL)isFirstPage {
    BOOL isFirstPage = self.page == 0;
    return isFirstPage;
}

- (NSUInteger)actualPage:(NSUInteger)aPage convert:(BOOL)convert {
    NSUInteger actualPage = aPage;
    if (convert) {
        if (self.doublePageModeOnFirstPage) {
            actualPage = floor(aPage/2.0);
        }else if(aPage) {
            actualPage = ceil(aPage/2.0);
        }
    }
    
    return actualPage;
}

// 0,1,2,3,4,5
- (NSUInteger)actualPage:(NSUInteger)aPage {
    return [self actualPage:aPage convert:[self isDualPageMode]];
}

- (NSUInteger)landscapePage:(NSUInteger)aPage convert:(BOOL)convert {
    NSUInteger landscapePage = aPage;
    if (convert) {
        if (self.doublePageModeOnFirstPage) {
            landscapePage = aPage*2;
        }else if(aPage) { // don't produce a -1
            landscapePage = aPage*2-1;
        }
    }
    return landscapePage;
}

// doublePageModeOnFirstPage: 0,0,1,1,2,2,3
// !doublePageModeOnFirstPage 0,1,1,2,2,3,3
- (NSUInteger)landscapePage:(NSUInteger)aPage {
    return [self landscapePage:aPage convert:[self isDualPageMode]];
}

// for showing the *human readable* page displayed
- (NSUInteger)humanReadablePageForPage:(NSUInteger)aPage {
    NSUInteger humanPage = aPage + 1; // increase on 1 (pages start at 1 for us)
    
    if (humanPage > [self.document pageCount]) {
        humanPage = [self.document pageCount];
    }
    
    return humanPage;
}

- (void)hidePopover:(NSNotification *)notification {
    if ([notification.object isKindOfClass:[self.popoverController.contentViewController class]]) {
        PSPDFLog(@"dismissing popover: %@", self.popoverController);
        [self.popoverController dismissPopoverAnimated:NO];
        self.popoverController = nil;
    }
}

// returns if the page would be or is a right page in dual page mode
- (BOOL)isRightPageInDoublePageMode:(NSUInteger)page {
    BOOL isRightPage = ((page%2 == 1 && self.isDoublePageModeOnFirstPage) || (page%2 == 0 && !self.isDoublePageModeOnFirstPage));
    return isRightPage;
}

- (void)frameChangedNotification:(NSNotification *)notification {
    UIView *changedView = (UIView *)notification.object;
    
    // as we could receive notifications from any controller, compare view
    if ([self isViewLoaded] && self.view == changedView && self.view.window && !rotationActive_) {
        
        // disable animation while reloading (else we get ugly animations)
        [UIView animateWithDuration:0 delay:0 options:UIViewAnimationOptionOverrideInheritedDuration animations:^{
            [self reloadData];
        } completion:nil];
    }
}

- (void)updateSettingsForRotation:(UIInterfaceOrientation)toInterfaceOrientation {
    // improves readability on iPhone
    if(!PSIsIpad()) {
        self.fitWidth = UIInterfaceOrientationIsLandscape(toInterfaceOrientation);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Delegate

- (void)setDelegate:(id<PSPDFViewControllerDelegate>)delegate {
    if (delegate != delegate_) {
        [self willChangeValueForKey:@"delegate"];
        delegate_ = delegate;
        delegateFlags_.delegateWillDisplayDocument = [delegate respondsToSelector:@selector(pdfViewController:willDisplayDocument:)];
        delegateFlags_.delegateDidDisplayDocument = [delegate respondsToSelector:@selector(pdfViewController:didDisplayDocument:)];
        delegateFlags_.delegateDidShowPageView = [delegate respondsToSelector:@selector(pdfViewController:didShowPageView:)];
        delegateFlags_.delegateDidRenderPageView = [delegate respondsToSelector:@selector(pdfViewController:didRenderPageView:)];
        delegateFlags_.delegateDidChangeViewMode = [delegate respondsToSelector:@selector(pdfViewController:didChangeViewMode:)];
        delegateFlags_.delegateDidTapOnPageView = [delegate respondsToSelector:@selector(pdfViewController:didTapOnPageView:info:coordinates:)];
        delegateFlags_.delegateDidTapOnAnnotation = [delegate respondsToSelector:@selector(pdfViewController:didTapOnAnnotation:page:info:coordinates:)];
        delegateFlags_.delegateShouldDisplayAnnotation = [delegate respondsToSelector:@selector(pdfViewController:shouldDisplayAnnotation:onPageView:)];
        delegateFlags_.delegateViewForAnnotation = [delegate respondsToSelector:@selector(pdfViewController:viewForAnnotation:onPageView:)];
        delegateFlags_.delegateAnnotationViewForAnnotation = [delegate respondsToSelector:@selector(pdfViewController:annotationView:forAnnotation:onPageView:)];
        delegateFlags_.delegateWillShowAnnotationView = [delegate respondsToSelector:@selector(pdfViewController:willShowAnnotationView:onPageView:)];
        delegateFlags_.delegateDidShowAnnotationView = [delegate respondsToSelector:@selector(pdfViewController:didShowAnnotationView:onPageView:)];
        delegateFlags_.delegateDidLoadPageView = [delegate respondsToSelector:@selector(pdfViewController:didLoadPageView:)];
        delegateFlags_.delegateWillUnloadPageView = [delegate respondsToSelector:@selector(pdfViewController:willUnloadPageView:)];
        [self didChangeValueForKey:@"delegate"];
    }
}

- (void)delegateWillDisplayDocument {
    if (delegateFlags_.delegateWillDisplayDocument) {
        [self.delegate pdfViewController:self willDisplayDocument:self.document];
    }
}

- (void)delegateDidDisplayDocument {
    if(delegateFlags_.delegateDidDisplayDocument) {
        [self.delegate pdfViewController:self didDisplayDocument:self.document];
    }
}

// helper, only look for PSPDFPageView if we really need it!
- (void)delegateDidShowPage:(NSUInteger)realPage {
    if (delegateFlags_.delegateDidShowPageView) {
        PSPDFPageView *pageView = [self pageViewForPage:realPage];
        [self delegateDidShowPageView:pageView];
    }
}

- (void)delegateDidShowPageView:(PSPDFPageView *)pageView {
    if (delegateFlags_.delegateDidShowPageView) {
        [self.delegate pdfViewController:self didShowPageView:pageView];
    }
}

- (void)delegateDidRenderPageView:(PSPDFPageView *)pageView {
    if (delegateFlags_.delegateDidRenderPageView) {
        [self.delegate pdfViewController:self didRenderPageView:pageView];
    }
}

- (void)delegateDidChangeViewMode:(PSPDFViewMode)viewMode {
    if (delegateFlags_.delegateDidChangeViewMode) {
        [self.delegate pdfViewController:self didChangeViewMode:viewMode];
    }
}

- (BOOL)delegateDidTapOnPageView:(PSPDFPageView *)pageView info:(PSPDFPageInfo *)pageInfo coordinates:(PSPDFPageCoordinates *)pageCoordinates {
    BOOL touchProcessed = NO;
    if (delegateFlags_.delegateDidTapOnPageView) {
        touchProcessed = [self.delegate pdfViewController:self didTapOnPageView:pageView info:pageInfo coordinates:pageCoordinates];
    }
    
    return touchProcessed;
}

- (BOOL)delegateDidTapOnAnnotation:(PSPDFAnnotation *)annotation page:(NSUInteger)page info:(PSPDFPageInfo *)pageInfo coordinates:(PSPDFPageCoordinates *)pageCoordinates {
    BOOL processed = NO;
    if (delegateFlags_.delegateDidTapOnAnnotation) {
        processed = [self.delegate pdfViewController:self didTapOnAnnotation:annotation page:page info:pageInfo coordinates:pageCoordinates];
    }
    return processed;
}

- (BOOL)delegateShouldDisplayAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView {
    BOOL shouldDisplayAnnotation = YES; // default
    if(delegateFlags_.delegateShouldDisplayAnnotation) {
        shouldDisplayAnnotation = [self.delegate pdfViewController:self shouldDisplayAnnotation:annotation onPageView:pageView];
    }
    return shouldDisplayAnnotation;
}

- (UIView <PSPDFAnnotationView> *)delegateViewForAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView {
    UIView <PSPDFAnnotationView> *annotationView = nil;
    if(delegateFlags_.delegateViewForAnnotation) {
        annotationView = [self.delegate pdfViewController:self viewForAnnotation:annotation onPageView:pageView];
    }
    return annotationView;
}

- (UIView <PSPDFAnnotationView> *)delegateAnnotationView:(UIView <PSPDFAnnotationView> *)annotationView forAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView {
    if(delegateFlags_.delegateAnnotationViewForAnnotation) {
        annotationView = [self.delegate pdfViewController:self annotationView:annotationView forAnnotation:annotation onPageView:pageView];
    }
    return annotationView;
}

- (void)delegateWillShowAnnotationView:(UIView <PSPDFAnnotationView> *)annotationView onPageView:(PSPDFPageView *)pageView {
    if(delegateFlags_.delegateWillShowAnnotationView) {
        [self.delegate pdfViewController:self willShowAnnotationView:annotationView onPageView:pageView];
    }
}

- (void)delegateDidShowAnnotationView:(UIView <PSPDFAnnotationView> *)annotationView onPageView:(PSPDFPageView *)pageView {
    if(delegateFlags_.delegateDidShowAnnotationView) {
        [self.delegate pdfViewController:self didShowAnnotationView:annotationView onPageView:pageView];
    }
}

- (void)delegateDidLoadPageView:(PSPDFPageView *)pageView {
    if (delegateFlags_.delegateDidLoadPageView) {
        [self.delegate pdfViewController:self didLoadPageView:pageView];
    }
}

- (void)delegateWillUnloadPageView:(PSPDFPageView *)pageView {
    if (delegateFlags_.delegateWillUnloadPageView) {
        [self.delegate pdfViewController:self willUnloadPageView:pageView];
    }
}

- (void)handleTouchUpForAnnotationIgnoredByDelegate:(PSPDFLinkAnnotationView *)annotationView {
    PSPDFAnnotation *annotation = annotationView.annotation;
    if (annotation.pageLinkTarget > 0) {
        [self scrollToPage:annotation.pageLinkTarget-1 animated:YES];
        
    }else if([annotation.siteLinkTarget length]) {
        if ([annotation.siteLinkTarget hasPrefix:@"mailto:"] && [MFMailComposeViewController canSendMail]) {
            // mail
            MFMailComposeViewController *mailVC = [[MFMailComposeViewController alloc] init];
            mailVC.mailComposeDelegate = self;
            NSString *email = [annotation.siteLinkTarget stringByReplacingOccurrencesOfString:@"mailto:" withString:@""];
            
            // fix encoding
            email = [email stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            
            // search for subject
            NSRange subjectRange = [email rangeOfString:@"?subject="];
            if (subjectRange.length > 0) {
                NSRange subjectContentRange = NSMakeRange(subjectRange.location + subjectRange.length, [email length] - subjectRange.location - subjectRange.length);
                NSString *subject = [email substringWithRange:subjectContentRange];
                if ([subject length]) {
                    [mailVC setSubject:subject];
                }
                
                // remove subject from email
                email = [email substringWithRange:NSMakeRange(0, subjectRange.location)];
            }
            
            [mailVC setToRecipients:[NSArray arrayWithObject:email]];
            mailVC.modalPresentationStyle = UIModalPresentationFormSheet;
            [[self masterViewController] presentModalViewController:mailVC animated:YES];
        }else {
            NSURL *URL = annotation.URL ?: [NSURL URLWithString:[annotation.siteLinkTarget pspdf_escapedString]];
            if ([[UIApplication sharedApplication] canOpenURL:URL]) {
                // special case if we want to use an inline browser
                if (annotation.isModal || linkAction_ == PSPDFLinkActionInlineBrowser) {
                    UINavigationController *webControllerNav = [PSPDFWebViewController modalWebViewWithURL:URL];
                    webControllerNav.navigationBar.tintColor = self.tintColor;
                    if (PSIsIpad()) {
                        CGSize targetSize = CGSizeMake(MAX(annotation.size.width, 200), MAX(annotation.size.height, 200));
                        if ([[annotation.options objectForKey:@"popover"] boolValue]) {
                            webControllerNav.topViewController.navigationItem.leftBarButtonItem = nil; // hide Done
                            UIPopoverController *popover = [[UIPopoverController alloc] initWithContentViewController:webControllerNav];
                            popover.popoverContentSize = targetSize;
                            CGRect popoverRect = [self.view convertRect:annotationView.frame fromView:annotationView.superview];
                            self.popoverController = popover;
                            [popover presentPopoverFromRect:popoverRect inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
                        }else {
                            if (!CGSizeEqualToSize(annotation.size, CGSizeZero)) {
                                webControllerNav.modalPresentationStyle = UIModalPresentationFormSheet;
                                [[self masterViewController] presentModalViewController:webControllerNav animated:YES];
                                // if we go to small, we hide the Done button
                                webControllerNav.view.superview.bounds = (CGRect){0, 0, targetSize};
                            }else {
                                [[self masterViewController] presentModalViewController:webControllerNav animated:YES];
                            }
                        }
                    }else {
                        [[self masterViewController] presentModalViewController:webControllerNav animated:YES];
                    }
                }else {
                    // web browser
                    if (linkAction_ == PSPDFLinkActionAlertView) {
                        PSPDFAlertView *alert = [PSPDFAlertView alertWithTitle:annotation.siteLinkTarget];
                        [alert setCancelButtonWithTitle:PSPDFLocalize(@"Cancel") block:nil];
                        [alert addButtonWithTitle:PSPDFLocalize(@"Open") block:^{
                            [[UIApplication sharedApplication] openURL:URL];
                        }];
                        [alert show];
                    }else if(linkAction_ == PSPDFLinkActionOpenSafari) {
                        [[UIApplication sharedApplication] openURL:URL];
                    }
                }
            }else {
                PSPDFLogWarning(@"Ignoring tap to %@ - UIApplication canOpenURL reports this is no registered handler.", annotation.siteLinkTarget);
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init { 
    return self = [self initWithDocument:nil]; // ensure to always call initWithDocument
}

- (id)initWithDocument:(PSPDFDocument *)document {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        PSPDFKitInitializeGlobals();
        NSNotificationCenter *nfc = [NSNotificationCenter defaultCenter];
        [nfc addObserver:self selector:@selector(hidePopover:) name:kDismissActivePopover object:nil];
        [nfc addObserver:self selector:@selector(frameChangedNotification:) name:kPSPDFViewControllerFrameChanged object:nil];
        viewMode_ = PSPDFViewModeDocument;
        viewModeControlVisible_ = YES;
        landscape_ = PSIsLandscape();
        document_ = document;    
        PSPDFLog(@"Open PDF with folder: %@", document.basePath);
        targetPageAfterRotate_ = 1; // on 0, first page would be omitted
        iPhoneThumbnailSizeReductionFactor_ = 0.5f;
        scrobbleBarEnabled_ = YES;
        positionViewEnabled_ = YES;
        toolbarEnabled_ = YES;
        scrollOnTapPageEndEnabled_ = YES;
        zoomingSmallDocumentsEnabled_ = YES;
        pageScrolling_ = PSPDFScrollingHorizontal;
        pageMode_ = PSIsIpad() ? PSPDFPageModeAutomatic : PSPDFPageModeSingle;
        statusBarStyleSetting_ = PSPDFStatusBarSmartBlack;
        linkAction_ = PSPDFLinkActionAlertView;
        printEnabled_ = NO;
        doublePageModeOnFirstPage_ = NO;
        lastPage_ = NSNotFound; // for delegates
        realPage_ = 0;  
        maximumZoomScale_ = 5.f;
        shadowEnabled_ = YES;
        pagePadding_ = 20.f;
        preloadedPagesPerSide_ = 0;
        pagingEnabled_ = YES;
        scrollingEnabled_ = YES;
        thumbnailSize_ = CGSizeMake(170.f, 220.f);
        annotationAnimationDuration_ = 0.25f;
        previousBarStyle_ = -1; // marker to save state one-time
    }
    return self;
}

- (void)dealloc {
    // "the deallocation problem" - it's not safe to dealloc a controller from a thread different than the main thread
    // http://developer.apple.com/library/ios/#technotes/tn2109/_index.html#//apple_ref/doc/uid/DTS40010274-CH1-SUBSECTION11
    NSAssert([NSThread isMainThread], @"Must run on main thread, see http://developer.apple.com/library/ios/#technotes/tn2109/_index.html#//apple_ref/doc/uid/DTS40010274-CH1-SUBSECTION11");
    PSPDFDeregisterObject(self);
    self.popoverController = nil; // ensure popover is hidden
    
    // cancel operations, nil out delegates
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preloadNextThumbnails) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kPSPDFViewControllerFrameChanged object:nil];
    
    if (document_) {
        // is called in viewWillDisappear, but call again if some forgot to relay that.
        [[PSPDFCache sharedPSPDFCache] stopCachingDocument:document_];
        document_.displayingPdfController = nil;
    }
    
    delegate_ = nil;    
    [[PSPDFGlobalLock sharedPSPDFGlobalLock] requestClearCacheAndWait:NO]; // request a clear cache
    
    // ensure delegate is nilled out on visible pages
    for(PSPDFScrollView *scrollView in [visiblePages_ setByAddingObjectsFromSet:recycledPages_]) {
        [scrollView releaseDocumentAndCallDelegate:NO];
    }
    
    // if pageCurl is enabled, nil out the delegates here.
    if ([pagingScrollView_ respondsToSelector:@selector(setPdfController:)]) {
        [(PSPDFPagedScrollView *)pagingScrollView_ setPdfController:nil];
    }
    documentInteractionController_.delegate = nil;
    pageViewController_.pdfController = nil;
    gridView_.actionDelegate = nil;
    gridView_.dataSource = nil;
    pagingScrollView_.delegate = nil;
    scrobbleBar_.pdfController = nil;  // deregisters KVO
    positionView_.pdfController = nil; // deregisters KVO
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView related

// searches the active root/modal viewController. We can't use our parent, we maybe are embedded.
- (UIViewController *)masterViewController {
    UIViewController *masterViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
    
    // use topmost modal view
    while (masterViewController.modalViewController) {
        masterViewController = masterViewController.modalViewController;
    }
    
    // get visible controller in a navigation controller
    if ([masterViewController isKindOfClass:[UINavigationController class]]) {
        masterViewController = [(UINavigationController *)masterViewController topViewController];
    }
    
    return masterViewController;
}

// helper
- (BOOL)isHorizontalScrolling {
    return pageScrolling_ == PSPDFScrollingHorizontal;
}

- (void)updatePagingContentSize {
    if (!self.isPageCurlEnabled) {
        CGRect pagingScrollViewFrame = [self frameForPageInScrollView];
        NSUInteger pageCount = [self actualPage:[self.document pageCount]];
        if ([self isDualPageMode] && (([self.document pageCount]%2==1 && self.doublePageModeOnFirstPage) || ([self.document pageCount]%2==0 && !self.doublePageModeOnFirstPage))) {
            pageCount++; // first page...
        }
        PSPDFLog(@"pageCount:%d, used page Count:%d", [self.document pageCount], pageCount);
        CGSize contentSize;
        if ([self isHorizontalScrolling]) {
            contentSize = CGSizeMake(pagingScrollViewFrame.size.width * pageCount, pagingScrollViewFrame.size.height);
        }else {
            contentSize = CGSizeMake(pagingScrollViewFrame.size.width, pagingScrollViewFrame.size.height * pageCount);
        }
        
        self.pagingScrollView.contentSize = contentSize;
    }
}

// page turn is a iOS5 exclusive feature
- (BOOL)isPageCurlEnabled {
    BOOL allowPageCurl = NO;
    PSPDF_IF_IOS5_OR_GREATER(allowPageCurl = pageCurlEnabled_;)
    
#ifdef _PSPDFKIT_DONT_USE_OBFUSCATED_PRIVATE_API_
    if (allowPageCurl) {
        PSPDFLogWarning(@"Unable to enable pageCurl as you disabled the needed fixes.");
        PSPDFLogWarning(@"Remove _PSPDFKIT_DONT_USE_OBFUSCATED_PRIVATE_API_ to enable the pageCurl feature.");
        allowPageCurl = NO;
    }
#endif
    
    return allowPageCurl;
}

- (void)createPagingScrollView {
    // remove current pdf display classes
    self.pagingScrollView.delegate = nil;
    [self.pagingScrollView removeFromSuperview];
    
    // remove paging view
    [self.pageViewController removeFromParentViewController];
    self.pageViewController = nil;
    
    CGRect bounds = self.view.bounds;
    
    if(self.isPageCurlEnabled) {
        PSPDFPageViewController *pageViewController = [[PSPDFPageViewController alloc] initWithPDFController:self];
        pageViewController.view.frame = bounds;
        pageViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addChildViewController:pageViewController];
        self.pageViewController = pageViewController;
        PSPDFPagedScrollView *pagedScrollView = [[[self classForClass:[PSPDFPagedScrollView class]] alloc] initWithPageViewController:pageViewController];
        [self.view insertSubview:pagedScrollView belowSubview:self.hudView];
        self.pagingScrollView = pagedScrollView;
    }else {
        if ([self isHorizontalScrolling]) {
            bounds.origin.x -= self.pagePadding;
            bounds.size.width += 2 * self.pagePadding;
        }else {
            bounds.origin.y -= self.pagePadding;
            bounds.size.height += 2 * self.pagePadding;
        }
        
        self.pagingScrollView = [[UIScrollView alloc] initWithFrame:bounds];
        self.pagingScrollView.pagingEnabled = self.isPagingEnabled;
        self.pagingScrollView.scrollEnabled = self.isScrollingEnabled;
        self.pagingScrollView.backgroundColor = [UIColor clearColor];
        self.pagingScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        if (kPSPDFKitDebugScrollViews) {
            self.pagingScrollView.backgroundColor = [UIColor colorWithRed:0.5f green:0.2f blue:0.f alpha:0.5f];
        }
        self.pagingScrollView.showsVerticalScrollIndicator = NO;
        self.pagingScrollView.showsHorizontalScrollIndicator = NO;
        self.pagingScrollView.delegate = self;
        [self.view insertSubview:self.pagingScrollView belowSubview:self.hudView];
        [self updatePagingContentSize];
        
        // Step 2: prepare to tile content
        self.recycledPages = [NSMutableSet setWithCapacity:4];
        self.visiblePages  = [NSMutableSet setWithCapacity:4];
        [self tilePages:NO];
    }
}

- (NSArray *)additionalLeftToolbarButtons {
    return nil;
}

// Helper to return an array of buttons for the left side of the HUD toolbar.
- (NSArray *)leftButtons {
    NSMutableArray *leftButtons = [NSMutableArray array];
    NSArray *additionalButtons = [self additionalLeftToolbarButtons];
    
    if (self.closeButton) {
        [leftButtons addObject:self.closeButton];
    }
    
    if (additionalButtons) {
        [leftButtons addObjectsFromArray:additionalButtons];
    }
    return leftButtons;
}

- (void)updateToolbars {
    if (self.isToolbarEnabled) {
        UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        space.width = 8;
        NSArray *leftButtons = [self leftButtons];
        self.leftToolbar.items = [self leftButtons];
        CGRect frame = self.leftToolbar.frame;
        frame.size.width = (self.closeButton ? 100.f : 0.f) + (35.f * [leftButtons count]);
        self.leftToolbar.frame = frame;
        
        // enable/disable buttons depending on document state
        BOOL isValidDocument = self.document.isValid;
        if([self.navigationItem.rightBarButtonItem.customView isKindOfClass:[UIToolbar class]]) {
            for (UIBarButtonItem *barButtonItem in ((UIToolbar *)self.navigationItem.rightBarButtonItem.customView).items) {
                if ([barButtonItem isKindOfClass:[UIBarButtonItem class]]) {
                    barButtonItem.enabled = isValidDocument;
                }
            }
        }
    }
}

- (UIBarButtonItem *)toolbarBackButton {
    // check if modal
    UIBarButtonItem *backButton = nil;
    if (self == [[[self navigationController] viewControllers] objectAtIndex:0]) {
        backButton = [[UIBarButtonItem alloc] initWithTitle:PSPDFLocalize(@"Documents")
                                                      style:UIBarButtonItemStyleBordered
                                                     target:self
                                                     action:@selector(documentButtonPressed)];
    }
    return backButton;
}

- (BOOL)isDarkHUD {
    BOOL isDarkHUD = !(self.statusBarStyleSetting & PSPDFStatusBarDisable) || [self statusBarStyle] != UIStatusBarStyleDefault;
    return isDarkHUD;
}

// Helper that returns the transparent height for the HUD. Used in toolbar scroll offset.
- (CGFloat)hudTransparencyOffset {
    CGFloat hudTransparencyOffset = self.isDarkHUD ? ((PSIsPortrait() || PSIsIpad()) ? 44.f : 30.f) : 0.f; // can't use self.navigationController.navigationBar.height, updates too late
    if (!PSIsIpad()) {
        CGRect statusBarRect = [UIApplication sharedApplication].statusBarFrame;
        hudTransparencyOffset += PSIsPortrait() ? statusBarRect.size.height : statusBarRect.size.width;
    }
    return hudTransparencyOffset;
}

- (void)updatePositionViewPosition {
    if (self.positionView) {
        CGFloat positionViewHeight = self.scrobbleBar ? self.scrobbleBar.frame.origin.y : self.view.frame.origin.y + self.view.frame.size.height;
        CGRect frame = CGRectIntegral(CGRectMake(self.view.frame.size.width/2, positionViewHeight - 30.f, 1, 1));
        self.positionView.frame = frame;
    }
}

// Helper that adds the position view if controller is configured to show it
- (void)addPositionViewToHUD {
    if (self.isPositionViewEnabled && !self.positionView && self.hudView) {
        PSPDFPositionView *positionView = [[[self classForClass:[PSPDFPositionView class]] alloc] initWithFrame:CGRectZero];
        positionView.pdfController = self;
        [self.hudView addSubview:positionView];
        self.positionView = positionView;
        [self updatePositionViewPosition];
    }
}

// Helper that initializes the scrobble bar
- (void)addScrobbleBarToHUD {
    if (self.isScrobbleBarEnabled && !self.scrobbleBar && self.hudView) {
        if (!self.scrobbleBar) {
            self.scrobbleBar = [[[self classForClass:[PSPDFScrobbleBar class]] alloc] init];
            self.scrobbleBar.pdfController = self;
        }
        [self.hudView addSubview:self.scrobbleBar];
    }
}

// allow changing the property at any time with rebuilding the toolbar.
- (void)setViewModeControlVisible:(BOOL)viewModeControlVisible {
    if (viewModeControlVisible != viewModeControlVisible_) {
        viewModeControlVisible_ = viewModeControlVisible;
        [self createToolbar];
    }
}

#define kButtonWidth 38.f
- (void)createToolbar {
    if (self.isToolbarEnabled) {
        self.closeButton = [self toolbarBackButton];
        
        // on iOS4, we need to build the toolbar manually
        PSPDF_IF_PRE_IOS5(self.leftToolbar = [[[self classForClass:[PSPDFTransparentToolbar class]] alloc] initWithFrame:CGRectMake(0.f, 0.f, 100.f, self.navigationController.navigationBar.frame.size.height)];        
                          self.leftToolbar.autoresizingMask = UIViewAutoresizingFlexibleHeight;
                          if(!tintColor_) {
                              self.leftToolbar.barStyle = !self.isDarkHUD ? UIBarStyleDefault : UIBarStyleBlack;
                          }else {
                              self.leftToolbar.tintColor = tintColor_;
                          }
                          if (self.closeButton) {
                              self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.leftToolbar];
                          });
        
        PSPDF_IF_IOS5_OR_GREATER(self.navigationItem.leftBarButtonItems = [self leftButtons];)
        
        viewModeSegment_ = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:[[PSPDFIconGenerator sharedGenerator] iconForType:PSPDFIconTypePage], [[PSPDFIconGenerator sharedGenerator] iconForType:PSPDFIconTypeThumbnails], nil]];        
        if (tintColor_) {
            viewModeSegment_.tintColor = tintColor_;
        }else {
            viewModeSegment_.tintColor = !self.isDarkHUD ? nil : [UIColor colorWithWhite:0.2f alpha:1.0f];
        }
        
        viewModeSegment_.selectedSegmentIndex = (gridView_ && !gridView_.hidden) ? 1 : 0;
        if (viewModeSegment_.selectedSegmentIndex == UISegmentedControlNoSegment) {
        }
        viewModeSegment_.segmentedControlStyle = UISegmentedControlStyleBar;
        [viewModeSegment_ addTarget:self action:@selector(viewModeSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        [viewModeSegment_ sizeToFit];
        self.viewModeButton = [[UIBarButtonItem alloc] initWithCustomView:viewModeSegment_];
        
        PSPDFTransparentToolbar *compoundView = [[[self classForClass:[PSPDFTransparentToolbar class]] alloc] init];
        compoundView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        compoundView.barStyle = !self.isDarkHUD ? UIBarStyleDefault : UIBarStyleBlack;        
        UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        space.width = 8.f;
        
        NSMutableArray *compoundItems = [NSMutableArray array];
        
        if ([UIPrintInteractionController isPrintingAvailable] && self.isPrintEnabled && self.document.allowsPrinting) {
            UIBarButtonItem *printButton = [[UIBarButtonItem alloc] initWithImage:[[PSPDFIconGenerator sharedGenerator] iconForType:PSPDFIconTypePrint] style:UIBarButtonItemStylePlain target:self action:@selector(printAction:)];
            [compoundItems addObjectsFromArray:[NSArray arrayWithObjects:printButton, space, nil]];
        }
        
        BOOL canOpenPdf = NO;
        if ([UIDocumentInteractionController class] && self.document.fileUrl) {
            UIDocumentInteractionController *docController = [UIDocumentInteractionController interactionControllerWithURL:self.document.fileUrl];
            if (docController) {
                canOpenPdf = [docController presentOpenInMenuFromRect:CGRectMake(0, 0, 1, 1) inView:[UIApplication sharedApplication].keyWindow animated:NO]; // Rect is not allowed to be CGRectZero
                [docController dismissMenuAnimated:NO];
            }
        }
        
        if (canOpenPdf && self.isOpenInEnabled) {
            UIBarButtonItem *openInButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openInAction:)];        
            [compoundItems addObjectsFromArray:[NSArray arrayWithObjects:openInButton, space, nil]];
        }
        
        if (self.document.isSearchEnabled) {
            UIBarButtonItem *searchButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(searchAction:)];
            [compoundItems addObjectsFromArray:[NSArray arrayWithObjects:searchButton, space, nil]];
        }
        
        // only enable outline if it's enabled and there actually is an outline
        if (self.document.isOutlineEnabled && [self.document.outlineParser.outline.children count] > 0) {
            UIBarButtonItem *outlineButton = [[UIBarButtonItem alloc] initWithImage:[[PSPDFIconGenerator sharedGenerator] iconForType:PSPDFIconTypeOutline] style:UIBarButtonItemStylePlain target:self action:@selector(outlineAction:)];
            [compoundItems addObjectsFromArray:[NSArray arrayWithObjects:outlineButton, space, nil]];
        }
        
        CGFloat viewModeSegmentWidth = [self isViewModeControlVisible] ? viewModeSegment_.frame.size.width : 0.f;
        compoundView.frame = CGRectMake(0.f, 0.f, viewModeSegmentWidth + (kButtonWidth * [compoundItems count] / 2) + 15.f, self.navigationController.navigationBar.frame.size.height);
        
        if ([self isViewModeControlVisible]) {
            [compoundItems addObject:viewModeButton_];
        }
        compoundView.items = compoundItems;
        
        if ([compoundView.items count]) {
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:compoundView];
            // Note: if IOS5's rightBarButtomItems would be used here, we would get a button style for search, which we don't want.
        }
        
        [self addScrobbleBarToHUD];
        [self addPositionViewToHUD];
    }
}

- (void)loadView {
    PSPDFViewControllerView *view = [[[self classForClass:[PSPDFViewControllerView class]] alloc] init];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.clipsToBounds = YES; // don't draw outside borders
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];    
    
    // setup HUD
    PSPDFHUDView *hudView = [[[self classForClass:[PSPDFHUDView class]] alloc] initWithFrame:self.view.bounds];
    hudView.backgroundColor  = [UIColor clearColor];
    hudView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    hudView.alpha = 0.f; // initially hidden
    [self.view addSubview:hudView];
    self.hudView = hudView;
    
    // set custom background color if needed
    self.view.backgroundColor = self.backgroundColor ? self.backgroundColor : [UIColor scrollViewTexturedBackgroundColor];
    
    // view debugging
    if(kPSPDFKitDebugScrollViews) {
        self.view.backgroundColor = [UIColor orangeColor];
    }
    
    // initally save last orientation
    lastOrientation_ = [[UIApplication sharedApplication] statusBarOrientation];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.viewVisible = YES;
    
    // configure toolbar if enabled
    if (self.isToolbarEnabled) {
        if (self.isDarkHUD) {
            navigationController_ = self.navigationController;
            
            if (previousBarStyle_ == -1) {
                previousBarStyle_ = self.navigationController.navigationBar.barStyle;
                previousBarStyleTranslucent_ = self.navigationController.navigationBar.translucent;
            }
            
            self.navigationController.navigationBar.barStyle = UIBarStyleBlackTranslucent; // TODO: deprecated
            self.navigationController.navigationBar.tintColor = tintColor_;
            self.navigationController.navigationBar.translucent = YES;
        }
    }
    
    // optimizes caching
    self.document.displayingPdfController = self;
    
    // save current status bar style and change to configured style
    self.savedStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
    self.savedStatusBarVisibility = [UIApplication sharedApplication].statusBarHidden;
    UIStatusBarStyle statusBarStyle = [self statusBarStyle];
    [self setStatusBarStyle:statusBarStyle animated:animated];
    
    // on iPhone, we may want fullscreen layout
    if (statusBarStyle == UIStatusBarStyleBlackTranslucent || self.statusBarStyleSetting & PSPDFStatusBarDisable) {
        self.wantsFullScreenLayout = YES;
    }
    
    // if statusbar hiding is requested, hide!
    if (self.statusBarStyleSetting & PSPDFStatusBarDisable) {
        [self setStatusBarHidden:YES withAnimation:animated ? UIStatusBarAnimationFade : UIStatusBarAnimationNone];
        
        // correct bounds for the navigation bar is calculated one runloop later.
        // if we just hide the statusbar here, we need to show/hide the HUD to fix the statusbar gap.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setHUDVisible:NO animated:NO];
            [self setHUDVisible:YES animated:animated];
        });
    }
    
    // update rotation specific settings
    [self updateSettingsForRotation:[UIApplication sharedApplication].statusBarOrientation];
    
    // create view only if view is appearing
    [self createToolbar];
    [self updateToolbars];
    
    // notify delegates that we're about to display a document
    [self delegateWillDisplayDocument];
    
    // finally load scrollview!
    [self reloadDataAndScrollToPage:self.realPage];
    
    // HUD is visible initially
    [self setHUDVisible:YES animated:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // relay any rotation that may happened after we were offscreen
    UIInterfaceOrientation currentOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (currentOrientation != lastOrientation_) {
        [self willRotateToInterfaceOrientation:currentOrientation duration:0.f];
        [self willAnimateRotationToInterfaceOrientation:currentOrientation duration:0.f];
        [self didRotateFromInterfaceOrientation:lastOrientation_];
        lastOrientation_ = currentOrientation;
    }
    
    [self delegateDidDisplayDocument];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self checkAndDismissPopoverForViewControllerClass:nil animated:animated];
    [self checkAndDismissDocumentInteractionControllerAnimated:animated];
    [self checkAndDismissPrintPopoverAnimated:animated];
    self.viewVisible = NO;
    
    // switch back to document mode
    [self setViewMode:PSPDFViewModeDocument animated:YES];
    
    // stop potential preload request
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preloadNextThumbnails) object:nil];
    
    if (self.document) {
        // optimizes caching
        self.document.displayingPdfController = nil;
    }
    
    // restore statusbar
    [self setStatusBarStyle:self.savedStatusBarStyle animated:animated];
    [self setStatusBarHidden:self.savedStatusBarVisibility withAnimation:animated ? UIStatusBarAnimationFade : UIStatusBarAnimationNone];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // self.navigationController is already nil here, so use the saved reference
    if (navigationController_.topViewController != self) {
        navigationController_.navigationBar.barStyle = previousBarStyle_;
        navigationController_.navigationBar.translucent = previousBarStyleTranslucent_;
    }
}

- (void)viewDidUnload {
    [super viewDidUnload];
    self.pagingScrollView.delegate = nil;
    self.pagingScrollView = nil;
    self.recycledPages = nil;
    self.visiblePages = nil;
    self.positionView.pdfController = nil; // deregisters KVO
    self.positionView = nil;
    self.scrobbleBar.pdfController = nil; // deregisters KVO
    self.scrobbleBar = nil;
    self.hudView = nil;
    self.closeButton = nil;
    self.leftToolbar = nil;
    self.viewModeButton = nil;
    gridView_.actionDelegate = nil;
    gridView_.dataSource = nil;
    gridView_ = nil;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    // we'll have to capture our target scroll page here, as pre-rotate maybe calls tilePages and changes current page...
    NSInteger lastRotationValue = targetPageAfterRotate_;
    targetPageAfterRotate_ = self.realPage;
    
    // now it get's tricky. make sure that after rotating back from two-page-mode to single page, we're showing the right page
    if ([self isDualPageMode] && lastRotationValue >= 0) {
        BOOL wasRightPage = [self isRightPageInDoublePageMode:lastRotationValue];
        BOOL singleFirstPage = !self.doublePageModeOnFirstPage && self.page == 0;
        if (wasRightPage && !singleFirstPage) {
            targetPageAfterRotate_++;
        }
    }
    
    // save orientation in case we rotate while off-screen
    lastOrientation_ = toInterfaceOrientation;
    
    [self updateSettingsForRotation:toInterfaceOrientation];
    
    // if there's a popover visible, hide it on rotation!
    if(self.popoverController.isPopoverVisible) {
        [self.popoverController dismissPopoverAnimated:NO];
        self.popoverController = nil;
    }
    
    rotationActive_ = YES;
    
    // disable tiled layer for rotation (fixes rotation problems with layer+background and tiledlayer artifacts on size change)
    for (PSPDFScrollView *page in self.visiblePages) {
        page.rotationActive = YES;
    }
    
    // PSPDFPageViewController's rotate is called before we come to willAnimateRotation, so set early.
    if (self.isPageCurlEnabled) {
        realPage_ = targetPageAfterRotate_;
    }
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    // rotation is handled implicit via the setFrame-notification
    if ([self isViewLoaded] && self.view.window) {
        PSPDF_IF_PRE_IOS5([self updateGridForOrientation];) // viewWillLayoutSubviews is iOS5 only
        [self updatePagingContentSize];
        [self scrollToPage:targetPageAfterRotate_ animated:NO hideHUD:NO];        
        rotationAnimationActive_ = YES; // important to only enable the flag here (or rotate animation and delegates freak out)
        [self tilePages:YES];
    }
    rotationAnimationActive_ = NO;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self updateGridForOrientation];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    rotationActive_ = NO;
    
    // If we don't reload after rotation, we get all kind of weird bugs breaking rotation altogether.
    // ([UIWindow beginDisablingInterfaceAutorotation] overflow on <UIWindow ...)
    // TODO: remains a todo, this may be fixed in future versions of iOS.
    if (self.isPageCurlEnabled) {
        [self reloadData];
    }
    
    // re-disable tiled layer for rotation`
    for (PSPDFScrollView *page in self.visiblePages) {
        page.rotationActive = NO;
    }
}

- (void)setPopoverController:(UIPopoverController *)popoverController {
    if (popoverController != popoverController_) {
        [self willChangeValueForKey:@"popoverController"];
        // hide last popup
        [popoverController_ dismissPopoverAnimated:NO];
        
        // most controller reference the pdfController, nil out delegate!
        if ([popoverController_ respondsToSelector:@selector(setDelegate:)]) {
            [popoverController_ setDelegate:nil];
        }
        
        popoverController_ = popoverController;
        popoverController_.delegate = self; // set delegate to be notified when popopver controller closes!
        
        
        // also query UINavigationController
        NSObject *popoverControllerSettable = popoverController.contentViewController;
        if ([popoverControllerSettable isKindOfClass:[UINavigationController class]]) {
            popoverControllerSettable = [(UINavigationController *)popoverControllerSettable topViewController];
        }
        
        // the contentController needs a reference to the popoverController to be able to dismiss itself
        if([popoverControllerSettable respondsToSelector:@selector(setPopoverController:)]) {
            [(PSPDFSearchViewController *)popoverControllerSettable setPopoverController:popoverController];
        }
        
        [self didChangeValueForKey:@"popoverController"];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

// corects landscape-values if entered in landscape
- (void)scrollToPage:(NSUInteger)page animated:(BOOL)animated hideHUD:(BOOL)hideHUD {
    if (!self.document || [self.document pageCount] == 0) {
        return; // silent abort of we don't have a document set
    }
    
    if (page >= [self.document pageCount]) {
        PSPDFLogWarning(@"Cannot scroll outside boundaries (%d), scrolling to last page.", page);
        // don't scroll to INT_MAX when pageCount is 0
        page = [self.document pageCount] ? [self.document pageCount]-1 : 0;
    }
    
    NSUInteger actualPage = [self actualPage:page];
    
    if (self.isViewVisible) {
        CGRect pageFrame = [self frameForPageAtIndex:actualPage];
        if ([self isHorizontalScrolling]) {
            pageFrame.origin.x -= self.pagePadding;
        }else {
            pageFrame.origin.y -= self.pagePadding;
        }
        
        if (hideHUD) {
            [self hideControlsIfPageMode];
        }
        
        if (!self.isPageCurlEnabled) {
            PSPDFLogVerbose(@"Scrolling to offset: %@", NSStringFromCGRect(pageFrame));
            [self.pagingScrollView setContentOffset:pageFrame.origin animated:animated];
            
            // if not animated, we have to manually tile pages.
            // also don't manually call when we're in the middle of rotation
            if (!animated && !(rotationActive_ && !rotationAnimationActive_)) {
                [self tilePages:NO];
            }
        }else {
            [pageViewController_ setPage:page animated:animated];
            self.page = actualPage;
        }
    }else {
        // not visible atm, just set page
        self.page = actualPage;
    }
}

- (void)scrollToPage:(NSUInteger)page animated:(BOOL)animated {
    [self scrollToPage:page animated:animated hideHUD:YES];
}

- (BOOL)scrollToNextPageAnimated:(BOOL)animated {
    if (![self isLastPage]) {
        NSUInteger nextPage = [self landscapePage:self.page+1];
        [self scrollToPage:nextPage animated:animated]; 
        return YES;
    }else {
        PSPDFLog(@"max page count of %d exceeded! tried:%d", [self.document pageCount], self.page+1);
        return NO;
    }
}

- (BOOL)scrollToPreviousPageAnimated:(BOOL)animated {
    if (![self isFirstPage]) {
        NSUInteger prevPage = [self landscapePage:self.page-1];
        [self scrollToPage:prevPage animated:animated];   
        return YES;
    }else {
        PSPDFLog(@"Cannot scroll < page 0");
        return NO;
    }
}

- (void)scrollRectToVisible:(CGRect)rect animated:(BOOL)animated {
    PSPDFPageView *pageView = [self pageViewForPage:self.page];
    [pageView.scrollView scrollRectToVisible:rect animated:animated];
}

- (void)zoomToRect:(CGRect)rect animated:(BOOL)animated {
    PSPDFPageView *pageView = [self pageViewForPage:self.page];
    [pageView.scrollView zoomToRect:rect animated:animated];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    if (backgroundColor_ != backgroundColor) {
        [self willChangeValueForKey:@"backgroundColor"];
        backgroundColor_ = backgroundColor;
        
        // only relay to view if loaded
        if ([self isViewLoaded]) {
            self.view.backgroundColor = backgroundColor;
        }
        [self didChangeValueForKey:@"backgroundColor"];
    }
}

- (void)setDocument:(PSPDFDocument *)document {
    if (document_ != document) {
        [self willChangeValueForKey:@"document"];
        if (document_) {
            [[PSPDFCache sharedPSPDFCache] stopCachingDocument:document_];
            document_.displayingPdfController = nil;
        }
        document_ = document;
        
        lastPage_ = NSNotFound; // reset last page
        [self reloadDataAndScrollToPage:0];
        [self didChangeValueForKey:@"document"];
    }
}

- (void)setPageMode:(PSPDFPageMode)pageMode {
    if (pageMode != pageMode_) {
        [self willChangeValueForKey:@"pageMode"];
        pageMode_ = pageMode;
        // don't rotate if rotation is active
        if (!rotationActive_) {
            [self reloadData];
        }
        [self didChangeValueForKey:@"pageMode"];
    }
}

- (void)setScrobbleBarEnabled:(BOOL)scrobbleBarEnabled {
    if (scrobbleBarEnabled != scrobbleBarEnabled_) {
        [self willChangeValueForKey:@"scrobbleBarEnabled"];
        scrobbleBarEnabled_ = scrobbleBarEnabled;
        
        // only adds the view if enabled, and hide initially
        [self addScrobbleBarToHUD];
        self.scrobbleBar.alpha = scrobbleBarEnabled ? 0.f : 1.f;
        
        // default animation, duration can be overridden when inside another animation block
        // still there's a chance thet we don't get the positionView (if HUD is not yet initialized)
        [UIView animateWithDuration:0.f delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
            if(scrobbleBarEnabled) {self.scrobbleBar.hidden = NO;}
            self.scrobbleBar.alpha = scrobbleBarEnabled ? 1.f : 0.f;
        } completion:^(BOOL finished) {
            self.scrobbleBar.hidden = !scrobbleBarEnabled;
        }];
        
        [self didChangeValueForKey:@"scrobbleBarEnabled"];
    }    
}

- (void)setPositionViewEnabled:(BOOL)positionViewEnabled {
    if (positionViewEnabled != positionViewEnabled_) {
        [self willChangeValueForKey:@"positionViewEnabled"];
        positionViewEnabled_ = positionViewEnabled;
        
        // only adds the view if enabled, and hide initially
        [self addPositionViewToHUD];
        self.positionView.alpha = positionViewEnabled ? 0.f : 1.f;
        
        // default animation, duration can be overridden when inside another animation block
        // still there's a chance thet we don't get the positionView (if HUD is not yet initialized)
        [UIView animateWithDuration:0.f delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
            if(positionViewEnabled) {self.positionView.hidden = NO;}
            self.positionView.alpha = positionViewEnabled ? 1.f : 0.f;
        } completion:^(BOOL finished) {
            self.positionView.hidden = !positionViewEnabled;
        }];
        
        [self didChangeValueForKey:@"positionViewEnabled"];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Tiling and page configuration

- (NSArray *)visiblePageNumbers {
    NSMutableArray *visiblePageNumbers = nil;
    
    if (self.isPageCurlEnabled) {
        visiblePageNumbers = [NSMutableArray arrayWithCapacity:2];
        NSInteger currentPage = self.pageViewController.page;
        if(currentPage >= 0) { // might be an invalid page (e.g. first page right only)
            [visiblePageNumbers addObject:[NSNumber numberWithInteger:currentPage]];
        }
        BOOL isDualPageMode = [self isDualPageMode];
        BOOL isNotLastPage = currentPage < (NSInteger)([self.document pageCount] + 1);
        if (isDualPageMode && isNotLastPage) {
            [visiblePageNumbers addObject:[NSNumber numberWithInteger:currentPage+1]];
        }
    }else {
        visiblePageNumbers = [NSMutableArray arrayWithCapacity:[self.visiblePages count]];
        for (PSPDFScrollView *scrollView in self.visiblePages) {
            if (scrollView.leftPage.document) {
                [visiblePageNumbers addObject:[NSNumber numberWithInteger:scrollView.leftPage.page]];
            }
            if (scrollView.rightPage.document) {
                [visiblePageNumbers addObject:[NSNumber numberWithInteger:scrollView.rightPage.page]];
            }
        }
    }
    return visiblePageNumbers;
}

// search for the page within PSPDFScollView
- (PSPDFPageView *)pageViewForPage:(NSUInteger)page {
    PSPDFPageView *pageView = nil;
    
    if (self.isPageCurlEnabled) {
        for (PSPDFSinglePageViewController *singlePage in self.pageViewController.viewControllers) {
            if (singlePage.page == page) {
                pageView = singlePage.pageView;
            }
        }
    }else {
        for (PSPDFScrollView *scrollView in self.visiblePages) {
            if (scrollView.leftPage.page == page) {
                pageView = scrollView.leftPage;
                break;
            }else if(scrollView.rightPage.document && scrollView.rightPage.page == page) {
                pageView = scrollView.rightPage;
                break;
            }
        }
    }
    
    return pageView;
}

// be sure to destroy pages before deallocating
- (void)setVisiblePages:(NSMutableSet *)visiblePages {
    if (visiblePages != visiblePages_) {
        [self destroyVisiblePages];
        visiblePages_ = visiblePages;
    }
}

// checks if a page is already displayed in the scrollview
- (BOOL)isDisplayingPageForIndex:(NSUInteger)pageIndex {
    BOOL foundPage = NO;
    for (PSPDFScrollView *page in self.visiblePages) {
        if (page.page == pageIndex) {
            foundPage = YES;
            break;
        }
    }
    return foundPage;
}

// stop all rendering
- (void)destroyVisiblePages {
    for (PSPDFScrollView *page in self.visiblePages) {        
        [page releaseDocumentAndCallDelegate:YES];
    }
    
    // no delegate calls needed, already recycled here
    for (PSPDFScrollView *page in self.recycledPages) {
        [page releaseDocumentAndCallDelegate:NO];
    }
}

- (PSPDFScrollView *)dequeueRecycledPage {
    PSPDFScrollView *page = [self.recycledPages anyObject];
    if (page) {
        [self.recycledPages removeObject:page];
    }
    return page;
}

// if there is a discrepancy between dual page mode, convert the pages first
- (void)convertPageOnDualModeChange:(PSPDFScrollView *)page currentPage:(NSUInteger)currentPage {
    if (page.dualPageMode != [self isDualPageMode]) {
        // we were dual paged, now converting back to single-pages (or vice versa)
        page.page = page.dualPageMode ? [self landscapePage:page.page convert:YES] : [self actualPage:page.page convert:YES];
        
        // make rotation awesome. (if the *right* page of a two-page set is visible, switch internal pages so that right page is not reused)
        if (page.dualPageMode && page.page == currentPage-1) {
            [page switchPages];
            page.page = currentPage;
        }
        
        page.dualPageMode = [self isDualPageMode];
    }    
}

// UIScrollView likes to scroll a few pixel "too far" - letting us create pages that we instantly destroy
// after ScrollerHeartBeat corrects the problem and finishes the scrolling. Compensate.
#define kScrollAnimationCompensator 3

- (void)tilePages:(BOOL)forceUpdate {
    // return early if paging scrollview is not yet created
    if (!self.pagingScrollView || self.isPageCurlEnabled) {
        return;
    }
    
    // if pagePadding is zero, we can't compensate scrollview movements
    CGFloat scrollAnimationCompensator = MIN(kScrollAnimationCompensator, pagePadding_);
    
    // Calculate which pages are visible
    CGRect visibleBounds = self.pagingScrollView.bounds;
    int firstNeededPageIndex, lastNeededPageIndex, primaryPageIndex;
    if ([self isHorizontalScrolling]) {
        firstNeededPageIndex = floorf((CGRectGetMinX(visibleBounds)+scrollAnimationCompensator) / CGRectGetWidth(visibleBounds));
        lastNeededPageIndex  = floorf((CGRectGetMaxX(visibleBounds)-scrollAnimationCompensator) / CGRectGetWidth(visibleBounds));
        primaryPageIndex = MAX(roundf(CGRectGetMinX(visibleBounds) / CGRectGetWidth(visibleBounds)), 0);
    }else {
        firstNeededPageIndex = floorf((CGRectGetMinY(visibleBounds)+scrollAnimationCompensator) / CGRectGetHeight(visibleBounds));
        lastNeededPageIndex  = floorf((CGRectGetMaxY(visibleBounds)-scrollAnimationCompensator) / CGRectGetHeight(visibleBounds));
        primaryPageIndex = MAX(roundf(CGRectGetMinY(visibleBounds) / CGRectGetHeight(visibleBounds)), 0);
    }
    
    // inclease index to better cache next pages
    firstNeededPageIndex -= self.preloadedPagesPerSide;
    lastNeededPageIndex += self.preloadedPagesPerSide;
    
    // make sure firstNeededPageIndex is within range
    firstNeededPageIndex = MAX(firstNeededPageIndex, 0);
    
    // make sure lastNeededPageIndex is limited to pageCount
    if ([self isDualPageMode]) { // two pages per slide
        lastNeededPageIndex = MIN(lastNeededPageIndex, floorf([self.document pageCount]/2));
    }else {
        lastNeededPageIndex = MIN(lastNeededPageIndex, [self.document pageCount] - 1);
    }
    
    // estimate page that is mostly visible
    PSPDFLogVerbose(@"first:%d last:%d page:%d", firstNeededPageIndex, lastNeededPageIndex, primaryPageIndex);
    
    
    // Recycle no-longer-visible pages (or convert for re-use while rotation)
    NSMutableSet *removedPages = [NSMutableSet set];
    for (PSPDFScrollView *page in self.visiblePages) {
        [self convertPageOnDualModeChange:page currentPage:[self landscapePage:primaryPageIndex]]; // used so we can re-use page on a dual page mode change (rotate, usually)
        if (page.page < firstNeededPageIndex || page.page > lastNeededPageIndex) {
            [page releaseDocumentAndCallDelegate:YES]; // remove set pdf, release memory (also, calls delegate!)
            [self.recycledPages addObject:page];   
            [removedPages addObject:page];
        }
    }
    [self.visiblePages minusSet:self.recycledPages];
    
    // add missing pages
    NSMutableSet *updatedPages = [NSMutableSet set];
    for (int pageIndex = firstNeededPageIndex; pageIndex <= lastNeededPageIndex; pageIndex++) {
        if (![self isDisplayingPageForIndex:pageIndex]) {
            PSPDFScrollView *page = [self dequeueRecycledPage];
            if ([removedPages containsObject:page]) {
                [removedPages removeObject:page];
            }
            if (page == nil) {
                page = [[[self classForClass:[PSPDFScrollView class]] alloc] init];
            }
            
            // add view
            [self.pagingScrollView addSubview:page];
            [self.visiblePages addObject:page];
            
            // configure it (also sends delegate events)
            [self configurePage:page forIndex:pageIndex];
            
            // ensure content is scrolled to top. (fitWidth + PSPDFScrollingVertical is not yet supported)
            if (self.fitWidth && self.pageScrolling == PSPDFScrollingHorizontal) {
                [page setContentOffset:CGPointMake(0, 0) animated:NO];                    
            }
            [updatedPages addObject:page];
        }
    }
    
    // only call removeFromSuperview for those pages that are not instantly re-used.
    // needs do be done in next runloop, else we may recursively invoke scrollViewDidScroll
    dispatch_async(dispatch_get_main_queue(), ^{
        [removedPages makeObjectsPerformSelector:@selector(removeFromSuperview)];
    });
    
    // if forced, configure all pages (used for rotation events)
    if (forceUpdate) {
        for (PSPDFScrollView *page in self.visiblePages) {
            if (![updatedPages containsObject:page]) {
                [self configurePage:page forIndex:page.page];
            }
        }
    }
    
    // finally, set new page
    self.page = primaryPageIndex;
}

// set properties within scrollview, update view
- (void)configurePage:(PSPDFScrollView *)page forIndex:(NSUInteger)pageIndex {
    page.dualPageMode = [self isDualPageMode];
    page.doublePageModeOnFirstPage = self.doublePageModeOnFirstPage;
    page.frame = [self frameForPageAtIndex:pageIndex];  
    page.zoomingSmallDocumentsEnabled = self.zoomingSmallDocumentsEnabled;
    page.shadowEnabled = self.shadowEnabled;
    page.scrollOnTapPageEndEnabled = self.scrollOnTapPageEndEnabled;
    page.fitWidth = [self isHorizontalScrolling] && self.isFittingWidth; // KNOWN LIMITATION
    page.pdfController = self;
    page.hidden = !self.document; // hide view if no document is set
    [page displayDocument:self.document withPage:pageIndex];
}

// preloads next document thumbnail
- (void)preloadNextThumbnails {
    PSPDFDocument *document = self.document;
    NSUInteger page = self.page;
    
    if (document) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            // cache next page's thumbnail
            if (page+1 < [document pageCount]) {
                PSPDFLogVerbose(@"Preloading thumbnails for page %d", page+1);
                [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:document page:page+1 size:PSPDFSizeThumbnail];
            }
            
            // start/update caching document
            [[PSPDFCache sharedPSPDFCache] cacheDocument:document startAtPage:page size:PSPDFSizeNative];
        });
        
        // fill document data cache in background (once)
        if (!documentRectCacheLoaded_) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                [document fillCache];
            });
            documentRectCacheLoaded_ = YES;
        }
    }
}

- (NSUInteger)page {
    NSUInteger page = [self actualPage:self.realPage];
    return page;
}

- (void)setRealPage:(NSUInteger)realPage {
    if (realPage != realPage_ || lastPage_ == NSNotFound) {
        [self willChangeValueForKey:@"realPage"];
        realPage_ = realPage;
        
        // only set title if we're allowed to make toolbar modifications, and only on iPad due to lack of space on iPhone
        if (PSIsIpad() && self.isToolbarEnabled) {
            self.navigationItem.title = self.document.title;
        }
        
        [self delegateDidShowPage:realPage]; // use helper to find PageView
        lastPage_ = realPage;        
        [self didChangeValueForKey:@"realPage"];
        
        // preload next thumbnails (so user doesn't see an empty image on scrolling)
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preloadNextThumbnails) object:nil];
        [self performSelector:@selector(preloadNextThumbnails) withObject:nil afterDelay:PSPDFIsCrappyDevice() ? 2.f : 1.f];        
    }
}

- (void)setPage:(NSUInteger)page {
    [self willChangeValueForKey:@"page"];
    self.realPage = [self landscapePage:page];
    [self didChangeValueForKey:@"page"];
}

- (void)reloadDataAndScrollToPage:(NSUInteger)page {
    // ignore multiple calls to reloadData
    if (_isReloading || rotationActive_) {
        return;
    }
    _isReloading = YES;
    // only update if window is attached
    if ([self isViewLoaded]) {
        [self createPagingScrollView];
        [self scrollToPage:page animated:NO hideHUD:NO];
        self.pagingScrollView.alpha = self.viewMode == PSPDFViewModeThumbnails ? 0.0 : 1.0;
        [self updateToolbars];
        [self.scrobbleBar updateToolbarForced];
        [self updatePositionViewPosition]; // depends on the scrobbleBar
        // don't forget the thumbnails
        [gridView_ reloadData]; // don't use self.gridView, as it's lazy init
    }
    _isReloading = NO;
}

- (void)reloadData {
    [self reloadDataAndScrollToPage:self.realPage];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Memory

- (void)didReceiveMemoryWarning {    
    [super didReceiveMemoryWarning];    
    PSPDFLog(@"Received memory warning. Relaying to scrollview. Removing recycled pages.");
    
    // release the pdf doc (clears internal cache)
    // this doesn't work if we have string references to the document somewhere else - so beware!
    [self.visiblePages makeObjectsPerformSelector:@selector(didReceiveMemoryWarning)];
    
    // remove all recycled pages
    [self.recycledPages removeAllObjects];
    
    // clear up the grid view
    if (gridView_ &&  self.viewMode == PSPDFViewModeDocument) {
        PSPDFLog(@"Clearing thumbnail grid.");
        [gridView_ removeFromSuperview];
        gridView_ = nil;
    }
    
    // if we're not visible, destroy all pages
    if (!self.view.window) {
        [self destroyVisiblePages];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - ScrollView delegate methods

- (void)setScrollingEnabled:(BOOL)scrollingEnabled {
    [self willChangeValueForKey:@"scrollingEnabled"];
    scrollingEnabled_ = scrollingEnabled;
    self.pagingScrollView.scrollEnabled = scrollingEnabled;
    [self didChangeValueForKey:@"scrollingEnabled"];
}

- (BOOL)shouldShowControls {
    BOOL atFirstPage = self.realPage == 0;
    BOOL atLastPage = self.realPage >= [self.document pageCount]-1;
    return atFirstPage || atLastPage;
}

- (void)hideControlsIfPageMode {
    if (self.viewMode == PSPDFViewModeDocument && ![self shouldShowControls]) {
        [self hideControls];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // before willAnimateRotate* is invoked, the system adapts the frame of the scrollView and
    // thus maybe contentOffset is adapted (which would cause automatic tiling, and would destroy the animation)
    // This is happening at the very last page of a document on rotate, so ignore the event here.
    if (rotationActive_ && !rotationAnimationActive_) {
        return;
    }
    
    scrolledDown_ = NO;
    if (lastContentOffset_ > scrollView.contentOffset.y) {
        scrolledDown_ = YES;
    }
    
    lastContentOffset_ = scrollView.contentOffset.y;
    
    [self tilePages:NO];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (self.viewMode == PSPDFViewModeDocument) {
        [self hideControls];
    }
    
    // invalidate target page (used to get correct page after rotation)
    targetPageAfterRotate_ = 1;
}

// called on finger up if user dragged. decelerate is true if it will continue moving afterwards
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [self hideControlsIfPageMode];
    
    if (!decelerate) {
        if ([self shouldShowControls]) {
            [self showControls];
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self hideControlsIfPageMode];
    if ([self shouldShowControls]) {
        [self showControls];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Frame calculations

- (CGRect)frameForPageInScrollView {
    CGRect bounds = self.view.bounds;
    
    if ([self isHorizontalScrolling]) {
        bounds.origin.x -= self.pagePadding;
        bounds.size.width += 2 * self.pagePadding;
    }else {
        bounds.origin.y -= self.pagePadding;
        bounds.size.height += 2 * self.pagePadding;
    }
    return bounds;
}

- (CGRect)frameForPageAtIndex:(NSUInteger)pageIndex {
    CGRect pagingScrollViewFrame = [self frameForPageInScrollView];
    CGRect pageFrame = pagingScrollViewFrame;
    
    if ([self isHorizontalScrolling]) {
        pageFrame.size.width -= (2 * self.pagePadding);
        pageFrame.origin.x = roundf(pagingScrollViewFrame.size.width * pageIndex) + self.pagePadding;
    }else {
        pageFrame.size.height -= (2 * self.pagePadding);
        pageFrame.origin.y = roundf(pagingScrollViewFrame.size.height * pageIndex) + self.pagePadding;
    }
    
    PSPDFLogVerbose(@"frameForPage: %@", NSStringFromCGRect(pageFrame));
    return pageFrame;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFGridViewDataSource

- (NSInteger)numberOfItemsInPSPDFGridView:(PSPDFGridView *)gridView {    
    return [self.document pageCount];
}

- (CGSize)PSPDFGridView:(PSPDFGridView *)gridView sizeForItemsInInterfaceOrientation:(UIInterfaceOrientation)orientation {
    CGSize thumbnailSize = self.thumbnailSize;    
    if (!PSIsIpad()) {
        thumbnailSize = CGSizeMake(floorf(thumbnailSize_.width * iPhoneThumbnailSizeReductionFactor_), floorf(thumbnailSize.height * iPhoneThumbnailSizeReductionFactor_));
    }
    return thumbnailSize;
}

- (PSPDFGridViewCell *)PSPDFGridView:(PSPDFGridView *)gridView cellForItemAtIndex:(NSInteger)cellIndex {
    CGSize size = [self PSPDFGridView:gridView sizeForItemsInInterfaceOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
    
    PSPDFThumbnailGridViewCell *cell = (PSPDFThumbnailGridViewCell *)[self.gridView dequeueReusableCell];
    if (!cell) {
        cell = [[[self classForClass:[PSPDFThumbnailGridViewCell class]] alloc] initWithFrame:CGRectMake(0.0f, 0.0f, size.width, size.height)];
    }
    
    // configure cell
    cell.document = self.document;
    cell.page = cellIndex;
    cell.siteLabel.text = [NSString stringWithFormat:@"%d", cellIndex+1];
    
    return cell;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFGrid

- (void)PSPDFGridView:(PSPDFGridView *)gridView didTapOnItemAtIndex:(NSInteger)position {
    [self scrollToPage:position animated:NO];
    [self setViewMode:PSPDFViewModeDocument animated:YES];
    
    // simple pop-animation
    PSPDFThumbnailGridViewCell *cell = (PSPDFThumbnailGridViewCell *)[gridView cellForItemAtIndex:position];
    __block BOOL originShadowEnabled, originLabelEnabled;
    [UIView animateWithDuration:0.25f delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
        originShadowEnabled = cell.shadowEnabled;
        originLabelEnabled = cell.showingSiteLabel;
        cell.shadowEnabled = NO;
        cell.imageView.bounds = CGRectMake(0, 0, cell.imageView.bounds.size.width + 50, cell.bounds.size.height + 50);
    } completion:^(BOOL finished) {
        cell.shadowEnabled = originShadowEnabled;
        cell.showingSiteLabel = originLabelEnabled;
    }];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIPopoverController

- (BOOL)popoverControllerShouldDismissPopover:(UIPopoverController *)popoverController {
    [self dismissKeyboardInSearchViewControllerPopover:popoverController];
    return YES;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
    self.popoverController = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - MFMailComposeViewControllerDelegate

// for email sheet on mailto: links
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
    [[self masterViewController] dismissModalViewControllerAnimated:YES];
}

@end

// override frame to get a change event
@implementation PSPDFViewControllerView

- (void)setFrame:(CGRect)frame {
    BOOL changed = !CGRectEqualToRect(frame, self.frame);
    [super setFrame:frame];
    
    if (changed && !CGRectIsEmpty(frame)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPSPDFViewControllerFrameChanged object:self];
    }
}

@end
