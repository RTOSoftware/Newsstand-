//
//  PSPDFLinkAnnotation.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFLinkAnnotationView.h"
#import <QuartzCore/QuartzCore.h>

@interface PSPDFLinkAnnotationView() {
    BOOL buttonPressing_;
    BOOL delayActive_;
}
@end

@implementation PSPDFLinkAnnotationView
@synthesize annotation = annotation_;
@synthesize hideSmallLinks = hideSmallLinks_;
@synthesize overspan = overspan_;
@synthesize pressedColor = pressedColor_;
@synthesize highlightBackgroundColor = highlightBackgroundColor_;
@dynamic cornerRadius;
@dynamic strokeWidth;
@dynamic borderColor;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (BOOL)shouldShowPressedColor {
    BOOL shouldShowPressedColor = delayActive_  || buttonPressing_;
    return shouldShowPressedColor;
}

- (void)restoreButtonBackgroundAnimated:(BOOL)animated {
    if(![self shouldShowPressedColor]) {
        [UIView animateWithDuration:0.25f delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
            self.backgroundColor = [UIColor clearColor];
        } completion:^(BOOL finished) {
            self.layer.mask = NULL;
        }];
    }
}

- (void)restoreBackgroundColorIfNotPressed {
    delayActive_ = NO;
    [self restoreButtonBackgroundAnimated:YES];
}

- (void)cancelTouchDown {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(touchDown) object:nil];    
}

- (void)touchDown {
    buttonPressing_ = YES;
    delayActive_ = YES;
    [self setNeedsDisplay];
    
    CALayer *mask = [CALayer layer];
    [mask setMasksToBounds:YES];
    [mask setCornerRadius:self.cornerRadius];
    mask.frame = self.bounds;
    [mask setBorderWidth:1.0f];
    [mask setBorderColor: [[UIColor blackColor] CGColor]];
    [mask setBackgroundColor: [[UIColor whiteColor] CGColor]];
    self.layer.mask = mask;
    self.backgroundColor = highlightBackgroundColor_;
    
    [self performSelector:@selector(restoreBackgroundColorIfNotPressed) withObject:nil afterDelay:1.5f];
}

- (void)touchUp {
    buttonPressing_ = NO;
    [self restoreButtonBackgroundAnimated:NO];
}

- (void)touchCancel {
    if (buttonPressing_) {
        buttonPressing_ = NO;
        delayActive_ = NO;    
        [self restoreButtonBackgroundAnimated:NO];
    }
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL inside = [super pointInside:point withEvent:event];
    if (!inside) {
        // first check if there is a LinkAnnotationView with the *exact* frame
        BOOL hasExactMatch = NO;
        for (UIView *view in self.superview.subviews) {
            CGPoint convertedPoint = [self convertPoint:point toView:view];
            if (CGRectContainsPoint(view.bounds, convertedPoint) && [view isKindOfClass:[self class]]) {
                hasExactMatch = YES;
                break;
            }
        }
        
        if (!hasExactMatch) {
            CGRect origRect = self.bounds;
            CGRect expandedRect = CGRectInset(origRect, -overspan_.width, -overspan_.height);
            inside = CGRectContainsPoint(expandedRect, point);
        }
    }
    return inside;
}

- (void)updateBorder {
    // style button
    BOOL hideBorder = hideSmallLinks_ && (self.frame.size.width < 6 || self.frame.size.height < 6);
    if (hideBorder) {
        self.strokeWidth = 0.f;
    }else {
        self.strokeWidth = 1.f;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        hideSmallLinks_ = YES;
        overspan_ = CGSizeMake(15, 15);
        highlightBackgroundColor_ = [UIColor colorWithWhite:0.f alpha:0.7f];
        
        self.layer.borderColor = [UIColor colorWithRed:0.055f green:0.129f blue:0.800f alpha:0.1f].CGColor; // Google-Blue :)
        self.layer.cornerRadius = 4.f;
        pressedColor_ = [UIColor colorWithWhite:0.7f alpha:0.5f];

        [self updateBorder];
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(restoreBackgroundColorIfNotPressed) object:nil];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    
    // wait until the next runloop to allow touble-taps
    [self cancelTouchDown];
    [self performSelector:@selector(touchDown) withObject:nil afterDelay:0.f];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self cancelTouchDown];
    [self touchCancel];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self cancelTouchDown];
    [self touchCancel];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)flashBackground {
    [self touchDown];
    [self touchUp];
}

- (void)setBorderColor:(UIColor *)borderColor {
    self.layer.borderColor = borderColor.CGColor;
}

- (UIColor *)borderColor {
    return [UIColor colorWithCGColor:self.layer.borderColor];
}

- (void)setStrokeWidth:(CGFloat)strokeWidth {
    self.layer.borderWidth = strokeWidth;
}

- (CGFloat)strokeWidth {
    return self.layer.borderWidth;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    self.layer.cornerRadius = cornerRadius;
}

- (CGFloat)cornerRadius {
    return self.layer.cornerRadius;
}

- (void)setHideSmallLinks:(BOOL)hideSmallLinks {
    hideSmallLinks_ = hideSmallLinks;
    [self updateBorder];
}

- (void)setOverspan:(CGSize)overspan {
    overspan_ = overspan;
}

@end
