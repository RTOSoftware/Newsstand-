//
//  PSPDFAlertView.m
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//
//  Loosely based on Landon Fullers "Using Blocks", Plausible Labs Cooperative.
//  http://landonf.bikemonkey.org/code/iphone/Using_Blocks_1.20090704.html
//

#import "PSPDFKitGlobal.h"
#import "PSPDFAlertView.h"

@interface PSPDFAlertView() <UIAlertViewDelegate> {
    NSMutableArray *blocks_;
}
@end

@implementation PSPDFAlertView

@synthesize alertView = view_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Static

+ (PSPDFAlertView *)alertWithTitle:(NSString *)title {
    return [[PSPDFAlertView alloc] initWithTitle:title message:nil];
}

+ (PSPDFAlertView *)alertWithTitle:(NSString *)title message:(NSString *)message {
    return [[PSPDFAlertView alloc] initWithTitle:title message:message];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithTitle:(NSString *)title message:(NSString *)message {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        view_ = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:nil otherButtonTitles:nil];
        blocks_ = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    view_.delegate = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setCancelButtonWithTitle:(NSString *)title block:(void (^)())block {
    assert([title length] > 0 && "cannot set empty button title");

    [self addButtonWithTitle:title block:block];
    view_.cancelButtonIndex = (view_.numberOfButtons - 1);
}

- (void)addButtonWithTitle:(NSString *)title block:(void (^)())block {
    assert([title length] > 0 && "cannot add button with empty title");
    [blocks_ addObject:block ? [block copy] : [NSNull null]];
    [view_ addButtonWithTitle:title];
}

- (void)show {
    [view_ show];

    // Ensure that the delegate (that's us) survives until the sheet is dismissed
    CFRetain((__bridge void *)self);
}

- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated {
    [view_ dismissWithClickedButtonIndex:buttonIndex animated:animated];
    [self alertView:view_ clickedButtonAtIndex:buttonIndex];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    // Run the button's block
    if (buttonIndex >= 0 && buttonIndex < [blocks_ count]) {
        id obj = [blocks_ objectAtIndex: buttonIndex];
        if (![obj isEqual:[NSNull null]]) {
            ((void (^)())obj)();
            // manually break potential retain cycle
            [blocks_ replaceObjectAtIndex:buttonIndex withObject:[NSNull null]];
        }
    }

    // AlertView to be dismissed, drop our self reference
    CFRelease((__bridge void *)self);
}

@end
