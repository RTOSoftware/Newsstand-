//
//  PSPDFHUDView.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFHUDView.h"

@implementation PSPDFHUDView

// only react on touches if it's a subview
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView * view in [self subviews]) {
        if (!view.hidden && view.userInteractionEnabled && [view pointInside:[self convertPoint:point toView:view] withEvent:event]) {
            return YES;
        }
    }
    return NO;
}

@end
