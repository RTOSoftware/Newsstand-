//
//  PSPDFPositionView.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFViewController.h"
#import "PSPDFPositionView.h"
#import "PSPDFDocument.h"
#import <QuartzCore/QuartzCore.h>

@implementation PSPDFPositionView

@synthesize label = label_;
@synthesize labelMargin = labelMargin_;
@synthesize pdfController = pdfController_;

static void *kPSPDFKVOToken;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (void)update {
    if (!pdfController_.document || pdfController_.document.pageCount == 0) {
        self.alpha = 0.f;
        label_.text = @"";
    }else {
        self.alpha = self.pdfController.viewMode == PSPDFViewModeDocument ? 1.f : 0.f;
        NSString *text = [NSString stringWithFormat:PSPDFLocalize(@"%d of %d"), pdfController_.realPage+1, pdfController_.document.pageCount];
        label_.text = text;
    }
    [self setNeedsLayout]; // recalculate outer frame
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame {
    if(self = [super initWithFrame:frame]) {
        self.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
        self.userInteractionEnabled = NO;
        labelMargin_ = 2;
        self.layer.cornerRadius = 3.f;
        self.backgroundColor = [UIColor colorWithWhite:0.4f alpha:0.7f];
        self.opaque = NO;
        label_ = [[UILabel alloc] init];
        label_.backgroundColor = [UIColor clearColor];
        label_.font = [UIFont boldSystemFontOfSize:14.f];
        label_.textColor = [UIColor whiteColor];
        label_.shadowColor = [UIColor blackColor];
        label_.shadowOffset = CGSizeMake(0, 1);
        [self addSubview:label_];
    }
    return self;
}

- (void)dealloc {
    self.pdfController = nil; // removes KVO
}

- (NSArray *)kvoValues {
    return [NSArray arrayWithObjects:NSStringFromSelector(@selector(realPage)), NSStringFromSelector(@selector(viewMode)), nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kPSPDFKVOToken) {
        [self update];
    }else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)setPdfController:(PSPDFViewController *)pdfController {
    if(pdfController != pdfController_) {
        PSPDFViewController *oldController = pdfController_;
        pdfController_ = pdfController;
        [[self kvoValues] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [oldController removeObserver:self forKeyPath:obj];
            [pdfController addObserver:self forKeyPath:obj options:idx == 0 ? NSKeyValueObservingOptionInitial : 0 context:&kPSPDFKVOToken];
        }];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)layoutSubviews {
    [super layoutSubviews];
    [label_ sizeToFit];
    label_.frame = CGRectMake(labelMargin_*4, labelMargin_, label_.frame.size.width, label_.frame.size.height);
    CGRect bounds = CGRectMake(0, 0, label_.frame.size.width+labelMargin_*8, label_.frame.size.height+labelMargin_*2);
    self.bounds = bounds;
    self.frame = CGRectIntegral(self.frame); // don't subpixel align centered item!
}

@end
