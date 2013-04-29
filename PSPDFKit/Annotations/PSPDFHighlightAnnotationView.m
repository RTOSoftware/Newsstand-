//
//  PSPDFHighlightAnnotationView.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFAnnotation.h"
#import "PSPDFHighlightAnnotationView.h"
#import <QuartzCore/QuartzCore.h>

@implementation PSPDFHighlightAnnotationView
@synthesize annotation = annotation_;
@synthesize button = button_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (void)touchDown {
    self.backgroundColor = [self.annotation.color colorWithAlphaComponent:0.8];
}

- (void)touchUp {
    self.backgroundColor = [self.annotation.color colorWithAlphaComponent:0.5];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        
        button_ = [UIButton buttonWithType:UIButtonTypeCustom];
        button_.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        button_.frame = CGRectMake(0.0, 0.0, frame.size.width, frame.size.height);
        [self addSubview:button_];
        
        [button_ addTarget:self action:@selector(touchDown) forControlEvents:UIControlEventTouchDown];
        [button_ addTarget:self action:@selector(touchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    return self;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setAnnotation:(PSPDFAnnotation *)annotation {
    if (annotation_ != annotation) {
        [self willChangeValueForKey:@"annotation"];
        annotation_ = annotation;
        [self didChangeValueForKey:@"annotation"];
        self.backgroundColor = [annotation.color colorWithAlphaComponent:0.5];
    }
}

@end
