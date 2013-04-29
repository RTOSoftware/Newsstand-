//
//  PSPDFOutlineCell.m
//  PSPDFKit
//
//  Copyright (c) 2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFOutlineCell.h"
#import "PSPDFOutlineElement.h"
#import "PSPDFIconGenerator.h"

@implementation PSPDFOutlineCell

@synthesize outlineElement = outlineElement_;
@synthesize delegate = delegate_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// Set transform according to expansion state.
- (void)updateOutlineButton {
    if (outlineElement_.isExpanded) {
        outlineDisclosure_.transform = CGAffineTransformMakeRotation(M_PI / 2);
    } else {
        outlineDisclosure_.transform = CGAffineTransformIdentity;
    }
    
    // hide button if no child elements
    outlineDisclosure_.hidden = outlineElement_.children.count == 0;
}

- (void)expandOrCollapse {
    [UIView animateWithDuration:0.25f delay:0.f options:0 animations:^{
        [self.delegate outlineCellDidTapDisclosureButton:self];
        [self updateOutlineButton];
    } completion:nil];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
		outlineDisclosure_ = [UIButton buttonWithType:UIButtonTypeCustom];
		[outlineDisclosure_ setBackgroundImage:[[PSPDFIconGenerator sharedGenerator] iconForType:PSPDFIconTypeForwardArrow] forState:UIControlStateNormal];
		[outlineDisclosure_ addTarget:self action:@selector(expandOrCollapse) forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:outlineDisclosure_];
	}
	return self;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setOutlineElement:(PSPDFOutlineElement *)outlineElement {
    if (outlineElement != outlineElement_) {
        outlineElement_ = outlineElement;
        
        CGFloat outlineIndent = 15.0f * outlineElement.level;
        self.indentationWidth = 32.0f + outlineIndent;
        self.indentationLevel = 1;
        self.textLabel.font = (outlineElement.level == 0) ? [UIFont boldSystemFontOfSize:17.0f] : [UIFont boldSystemFontOfSize:15.0f];
        self.textLabel.text = outlineElement.title;
        
        outlineDisclosure_.frame = CGRectMake(outlineIndent, 0.f, 44.f, 44.f);
        [self updateOutlineButton];
    }
}

@end
