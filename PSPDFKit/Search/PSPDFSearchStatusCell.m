//
//  PSPDFSearchStatusCell.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFSearchStatusCell.h"
#import "PSPDFKit.h"

#define kPSPDFSpinnerTag 235256

@implementation PSPDFSearchStatusCell

@synthesize spinner = spinner_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

// allow centered labels
- (void)layoutSubviews {
    [super layoutSubviews];
    // center textLabel so that we can put the spinner on the left side
    [self.textLabel sizeToFit];
    self.textLabel.frame = CGRectIntegral(CGRectMake((self.frame.size.width-self.textLabel.frame.size.width)/2, self.textLabel.frame.origin.y, self.textLabel.frame.size.width, self.textLabel.frame.size.height));
    UIActivityIndicatorView *spinner = [self spinner];
    spinner.frame = CGRectMake(self.textLabel.frame.origin.x - 25, self.textLabel.frame.origin.y, spinner.frame.size.width, spinner.frame.size.height);
    self.detailTextLabel.frame = CGRectMake(0, self.detailTextLabel.frame.origin.y, self.frame.size.width, self.detailTextLabel.frame.size.height);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (UIActivityIndicatorView *)spinner {
    UIActivityIndicatorView *spinner = (UIActivityIndicatorView *)[self viewWithTag:kPSPDFSpinnerTag];
    return spinner;
}

- (void)updateCellWithSearchStatus:(PSPDFSearchStatus)searchStatus results:(NSUInteger)results {
    UIActivityIndicatorView *spinner = [self spinner];
    if (!spinner) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.textLabel.font = [UIFont boldSystemFontOfSize:14];
        self.textLabel.textAlignment = UITextAlignmentCenter;
        self.detailTextLabel.textAlignment = UITextAlignmentCenter;
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [spinner sizeToFit];
        [spinner startAnimating];
        [self addSubview:spinner];
        spinner.center = self.center;
        spinner.frame = CGRectIntegral(spinner.frame); // be sure we're not misaligned
        spinner.tag = kPSPDFSpinnerTag;
    }
    
    CGFloat spinnerAlpha = 0.f;
    NSString *text = @"";
    NSString *subText = @"";
    switch (searchStatus) {
        case PSPDFSearchIdle:
            break;
        case PSPDFSearchActive: {
            spinnerAlpha = 1.f;
            text = PSPDFLocalize(@"Searching...");
        }break;
        case PSPDFSearchFinished: {
            text = PSPDFLocalize(@"Search Completed");
            if (results == 0) {
                subText = PSPDFLocalize(@"No matches found");
            }else if(results == 1) {
                subText = PSPDFLocalize(@"One match found");
            }else {
                subText = [NSString stringWithFormat:PSPDFLocalize(@"%d matches found"), results];
            }
        }break;
        case PSPDFSearchCancelled: {
            text = PSPDFLocalize(@"Search Cancelled");
        }break;
            
        default:
            break;
    }
    spinner.alpha = spinnerAlpha;
    self.textLabel.text = text;
    self.detailTextLabel.text = subText;
    [self setNeedsLayout];
}

@end
