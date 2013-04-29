//
//  PSPDFThumbnailGridViewCell.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "PSPDFKit.h"

@interface PSPDFThumbnailGridViewCell() {
    CALayer *shadowLayer_;
}
@end

@implementation PSPDFThumbnailGridViewCell

@synthesize imageView = imageView_;
@synthesize siteLabel = siteLabel_;
@synthesize document = document_;
@synthesize page = page_;
@synthesize shadowEnabled = shadowEnabled_;
@synthesize showingSiteLabel = showingSiteLabel_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

/// Creates the shadow. Subclass to change. Returns a CGPathRef.
- (id)pathShadowForView:(UIView *)imgView {
    CGSize size = imgView.bounds.size;    
    UIBezierPath *path = nil;
    
    CGFloat moveShadow = -8;
    path = [UIBezierPath bezierPathWithRect:CGRectMake(moveShadow, moveShadow, size.width+fabs(moveShadow/2), size.height+fabs(moveShadow/2))];
    
    // copy path, else ARC instantly deallocates the UIBezierPath backing store
    id cgPath = path ? (__bridge_transfer id)CGPathCreateCopy(path.CGPath) : nil;
    return cgPath;
}

- (void)updateShadow {
    if (!shadowLayer_) {
        shadowLayer_ = [[CALayer alloc] init];
        [self.contentView.layer insertSublayer:shadowLayer_ atIndex:1];
        [self.contentView bringSubviewToFront:self.imageView];
    }
    
    // enable/disable shadows
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CALayer *shadowLayer = shadowLayer_;
    shadowLayer.shadowPath = (__bridge CGPathRef)[self pathShadowForView:self.imageView];
    shadowLayer.frame = self.imageView.frame;
    
    if (self.isShadowEnabled && shadowLayer.shadowRadius != 4.f) {
        shadowLayer.shadowColor = [UIColor blackColor].CGColor;
        shadowLayer.shadowOpacity = 0.5f;
        shadowLayer.shadowOffset = CGSizeMake(6.0f, 6.0f);
        shadowLayer.shadowRadius = 2.0f;
        shadowLayer.masksToBounds = NO;
    }else if(!self.isShadowEnabled && shadowLayer.shadowRadius > 0.f) {
        shadowLayer.shadowRadius = 0.f;
        shadowLayer.shadowOpacity = 0.f;
    }
    [CATransaction commit];
}

#define ksiteLabelHeight 24
- (void)updateSiteLabel {
    if (self.isShowingSiteLabel && !siteLabel_.superview) {
        siteLabel_ = [[UILabel alloc] initWithFrame:CGRectZero];         
        siteLabel_.backgroundColor = [UIColor colorWithWhite:0.f alpha:0.7f];
        siteLabel_.textColor = [UIColor colorWithWhite:0.8f alpha:1.f];
        siteLabel_.shadowColor = [UIColor blackColor];
        siteLabel_.shadowOffset = CGSizeMake(1.f, 1.f);
        siteLabel_.textAlignment = UITextAlignmentCenter;
        siteLabel_.font = [UIFont boldSystemFontOfSize:16];
        [self.contentView addSubview:siteLabel_];
    }else if(!self.isShowingSiteLabel && siteLabel_.superview) {
        [siteLabel_ removeFromSuperview];
    }
    
    // calculate new frame and position correct
    siteLabel_.frame = CGRectMake(self.imageView.frame.origin.x, self.imageView.frame.origin.y+self.imageView.frame.size.height-ksiteLabelHeight, self.imageView.frame.size.width, ksiteLabelHeight);
    if (siteLabel_.superview) {
        [self.contentView bringSubviewToFront:siteLabel_];
    }
}

- (void)setImageSize:(CGSize)imageSize {
    // set aspect ratio and center image    
    if (!CGSizeEqualToSize(imageSize, CGSizeZero)) {
        CGFloat scale = [UIImage pspdf_scaleForImageSize:imageSize bounds:self.bounds.size];
        CGSize thumbSize = CGSizeMake(roundf(imageSize.width * scale), roundf(imageSize.height * scale));
        self.imageView.frame = CGRectMake(roundf((self.frame.size.width-thumbSize.width)/2.f), roundf((self.frame.size.height-thumbSize.height)/2.f), thumbSize.width, thumbSize.height);
    }else {
        self.imageView.frame = self.bounds;
    }
    [self updateShadow];
    [self updateSiteLabel];
}

- (void)updateImageViewBackgroundColor {
    imageView_.backgroundColor = imageView_.image ? [UIColor clearColor] : [UIColor colorWithWhite:1.f alpha:0.8f];
}

- (void)setImage:(UIImage *)image animated:(BOOL)animated {
    if (animated) {
        CATransition *transition = [CATransition animation];
        transition.duration = 0.25f;
        transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        transition.type = kCATransitionFade;
        [self.imageView.layer addAnimation:transition forKey:@"image"];
    }
    
    self.imageView.image = image;
    CGSize imageSize = image ? image.size : CGSizeZero;
    [self setImageSize:imageSize];    
    [self updateImageViewBackgroundColor];
}

// custom queue for thumbnail parsing
- (NSOperationQueue *)thumbnailQueue {
    static NSOperationQueue *queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 4;
        queue.name = @"PSPDFThumbnailQueue";
    });
    return queue;
}

// tries to load thumbnail - loads it async if not existing
- (void)loadImageAsync {
    if (!self.document) {
        PSPDFLogWarning(@"Document is nil!");
        return;
    }
    
    // capture data
    NSUInteger page = self.page;
    PSPDFDocument *document = self.document;
    
    // only returns image directly if it's already in memory
    UIImage *cachedImage = [[PSPDFCache sharedPSPDFCache] imageForDocument:document page:page size:PSPDFSizeThumbnail];
    if (cachedImage) {
        [self setImage:cachedImage animated:NO];
    }else {
        // at least try to set correct aspect ratio
        PSPDFPageInfo *pageInfo = nil;
        if ([self.document hasPageInfoForPage:self.page]) {
            pageInfo = [self.document pageInfoForPage:self.page];
        }else {
            // just try to get the pageInfo for the last detected page instead (will work in many cases)
            pageInfo = [self.document nearestPageInfoForPage:self.page];
        }
        
        if (pageInfo) {
            [self setImageSize:pageInfo.pageRect.size];
        }else {
            [self setImageSize:self.bounds.size];
        }
        
        // load image in background
        NSBlockOperation *blockOperation = [NSBlockOperation blockOperationWithBlock:^{
            @autoreleasepool {
                BOOL shouldPreload = YES;
                UIImage *thumbnailImage = nil;
                
                // try to load image directly from document
                NSURL *thumbImagePath = [document thumbnailPathForPage:page];
                if (thumbImagePath) {
                    thumbnailImage = [UIImage pspdf_preloadedImageWithContentsOfFile:[thumbImagePath path] useJPGTurbo:[PSPDFCache sharedPSPDFCache].useJPGTurbo];
                    
                    if (thumbnailImage) {
                        [[PSPDFCache sharedPSPDFCache] cacheImage:thumbnailImage document:document page:page size:PSPDFSizeThumbnail];
                    }
                    
                    // external thumbs may are too large - need shrinking (or else system is slow in scrolling)
                    if (thumbnailImage && ((thumbnailImage.size.width / self.bounds.size.width > kPSPDFShrinkOwnImagesTresholdFactor) ||
                        (thumbnailImage.size.height / self.bounds.size.height > kPSPDFShrinkOwnImagesTresholdFactor))) {
                        PSPDFLogVerbose(@"apply additional shrinking for image cells to %@", NSStringFromCGRect(self.bounds));
                        
                        thumbnailImage = [thumbnailImage pspdf_imageToFitSize:self.bounds.size method:PSPDFImageResizeCrop honorScaleFactor:YES];
                        shouldPreload = NO;
                    }
                }
                
                // if we still miss a thumbnail, try to get a cached one from the cache
                if (!thumbnailImage) {
                    thumbnailImage = [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:document page:page size:PSPDFSizeThumbnail preload:shouldPreload];
                }
                                
                // we may or may not have the thumbnail now
                if (thumbnailImage) {                    
                    // set image in main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (page == self.page && document == self.document) {
                            [self setImage:thumbnailImage animated:YES];
                        }else {
                            PSPDFLogVerbose(@"Ignoring loaded thumbnail...");
                        }
                    });        
                }
            }
        }];
        [[self thumbnailQueue] addOperation:blockOperation];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = NO; // allow drop shadow
        self.exclusiveTouch = YES; // don't allow touching more cells at once
        
        UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
        view.layer.masksToBounds = NO;
        view.layer.shadowOffset = CGSizeMake(5, 5);
        view.layer.shadowPath = [UIBezierPath bezierPathWithRect:view.bounds].CGPath;
        view.layer.shadowRadius = 8;
        self.contentView = view;
        
        imageView_ = [[UIImageView alloc] initWithFrame:frame];
        imageView_.clipsToBounds = YES;
        imageView_.contentMode = UIViewContentModeScaleAspectFill;
        [self updateImageViewBackgroundColor];
        
        /*
         // make it round, and rasterize it for speed
         imageView_.layer.cornerRadius = 3;
         self.layer.shouldRasterize = YES;
         self.layer.rasterizationScale = [[UIScreen mainScreen] scale];
         */
        
        [self.contentView addSubview:imageView_];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.contentView.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        
        // shadow is enabled per default
        shadowEnabled_ = YES;
        showingSiteLabel_ = YES;
        
        [[PSPDFCache sharedPSPDFCache] addDelegate:self];
        [self setNeedsLayout];
    }
    return self;
}

- (void)dealloc {
    [[PSPDFCache sharedPSPDFCache] removeDelegate:self];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    self.alpha = 0.7f;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    self.alpha = 1.0f;    
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.alpha = 1.0f;   
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setPage:(NSUInteger)page {
    page_ = page;
    
    if (self.document) {
        [self loadImageAsync];
    }
}

- (void)setShadowEnabled:(BOOL)shadowEnabled {
    shadowEnabled_ = shadowEnabled;
    [self setNeedsLayout];
}

- (void)setShowingSiteLabel:(BOOL)showingSiteLabel {
    showingSiteLabel_ = showingSiteLabel;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateShadow];
    [self updateSiteLabel];
}

- (void)prepareForReuse {
    self.page = 0;
    imageView_.image = nil;
    [self updateSiteLabel];
    [self updateImageViewBackgroundColor];
    [super prepareForReuse];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFCacheDelegate

- (void)didCachePageForDocument:(PSPDFDocument *)pdfdocument page:(NSUInteger)aPage image:(UIImage *)cachedImage size:(PSPDFSize)size {
    if (self.document == pdfdocument && aPage == self.page && size == PSPDFSizeThumbnail) {
        [self setImage:cachedImage animated:YES];
    }
}

@end
