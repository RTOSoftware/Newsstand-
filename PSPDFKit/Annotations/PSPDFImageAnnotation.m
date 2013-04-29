//
//  PSPDFImageAnnotation.m
//  PSPDFKit
//
//  Copyright (c) 2012 Peter Steinberger. All rights reserved.
//  Thanks to Niklas Saers / Trifork A/S for the contribution.
//

#import "PSPDFImageAnnotation.h"
#import "PSPDFKitGlobal.h"
#import "PSPDFAnnotation.h"

@implementation PSPDFImageAnnotation

@synthesize annotation = annotation_;
@synthesize URL = URL_;
@synthesize imageView = imageView_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (UIImageView *)imageView {
    if (!imageView_) {
        imageView_ = [[UIImageView alloc] initWithFrame:self.frame];
        imageView_.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imageView_.contentMode = UIViewContentModeScaleAspectFit;
        imageView_.frame = self.bounds;
        [self addSubview:imageView_];
        
        // try loading the image
        if (URL_) {
            UIImage *image = [UIImage imageWithContentsOfFile:[self.URL path]];
            imageView_.image = image;
        }
    }
    return imageView_;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        PSPDFRegisterObject(self);
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    imageView_ = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setURL:(NSURL *)URL {
    if (URL != URL_) {
        URL_ = URL;
        self.imageView.image = [UIImage imageWithContentsOfFile:[self.URL path]];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFAnnotationView

/// page is displayed
- (void)didShowPage:(NSUInteger)page {
    [self imageView]; // access imageView to be sure it's created.
}

@end
