//
//  NSMutableAttributedString+PSPDFKitAdditions.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "NSMutableAttributedString+PSPDFKitAdditions.h"
#import <CoreText/CoreText.h>

PSPDF_FIX_CATEGORY_BUG(NSMutableAttributedStringPSPDFKitAdditions)

@implementation NSMutableAttributedString (PSPDFKitAdditions)

// Borrowed from Olivier Halligon, OHAttributedString. Thanks!
- (void)pspdfSetFontName:(NSString *)fontName size:(CGFloat)size range:(NSRange)range {
	// kCTFontAttributeName
	CTFontRef aFont = CTFontCreateWithName((__bridge CFStringRef)fontName, size, NULL);
	if (!aFont) return;
	[self removeAttribute:(NSString *)kCTFontAttributeName range:range]; // Work around for Apple leak
	[self addAttribute:(NSString *)kCTFontAttributeName value:(__bridge id)aFont range:range];
	CFRelease(aFont);
}

- (void)pspdfSetFont:(UIFont *)font range:(NSRange)range {
	[self pspdfSetFontName:font.fontName size:font.pointSize range:range];
}

- (void)pspdfSetFontName:(NSString *)fontName size:(CGFloat)size {
	[self pspdfSetFontName:fontName size:size range:NSMakeRange(0, [self length])];
}

- (void)pspdfSetFont:(UIFont *)font {
	[self pspdfSetFontName:font.fontName size:font.pointSize];
}

@end
