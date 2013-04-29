//
//  PSPDFAnnotation.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
// 
//  Rect-Parsing code partially based on code by Sorin Nistor. Thanks!
//  Copyright (c) 2011-2012 Sorin Nistor. All rights reserved. This software is provided 'as-is', without any express or implied warranty.
//  In no event will the authors be held liable for any damages arising from the use of this software.
//  Permission is granted to anyone to use this software for any purpose, including commercial applications,
//  and to alter it and redistribute it freely, subject to the following restrictions:
//  1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software.
//     If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source distribution.
//

#import "UIColor+PSPDFKitAdditions.h"
#import "PSPDFAnnotation.h"
#import "PSPDFKit.h"

@implementation PSPDFAnnotation

@synthesize pageLinkTarget = pageLinkTarget_;
@synthesize siteLinkTarget = siteLinkTarget_;
@synthesize pdfRectangle = pdfRectangle_;
@synthesize page = page_;
@synthesize type = type_;
@synthesize URL = URL_;
@synthesize document = document_;
@synthesize contents = contents_;
@synthesize color = color_;
@synthesize options = options_;
@dynamic overlayAnnotation;
@dynamic uid;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithPDFDictionary:(CGPDFDictionaryRef)annotationDictionary {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        // Normalize and cache the annotation rect definition for faster hit testing.
        CGPDFArrayRef rectArray = NULL;
        CGPDFDictionaryGetArray(annotationDictionary, "Rect", &rectArray);
        if (rectArray != NULL) {
            CGPDFReal llx = 0;
            CGPDFArrayGetNumber(rectArray, 0, &llx);
            CGPDFReal lly = 0;
            CGPDFArrayGetNumber(rectArray, 1, &lly);
            CGPDFReal urx = 0;
            CGPDFArrayGetNumber(rectArray, 2, &urx);
            CGPDFReal ury = 0;
            CGPDFArrayGetNumber(rectArray, 3, &ury);
            
            if (llx > urx) {
                CGPDFReal temp = llx;
                llx = urx;
                urx = temp;
            }
            if (lly > ury) {
                CGPDFReal temp = lly;
                lly = ury;
                ury = temp;
            }
            
            pdfRectangle_ = CGRectMake(llx, lly, urx - llx, ury - lly);
        }
        
        CGPDFStringRef contents;
        
        // Get any associated contents (arbitary text entered by the user) from this dictionary
        if (CGPDFDictionaryGetString(annotationDictionary, "Contents", &contents)) {
            contents_ = (__bridge_transfer NSString *)CGPDFStringCopyTextString(contents);
            PSPDFLog(@"%@ contents is \"%@\"", self, contents_);
        }
        
        CGPDFArrayRef components;
        
        // Get the components of a color optionally used to present the annotation
        if (CGPDFDictionaryGetArray(annotationDictionary, "C", &components)) {
            
            color_ = [[UIColor alloc] initWithCGPDFArray:components];
        }
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    document_ = nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ type:%d rect:%@ targetPage:%d targetSite:%@ URL:%@ (sourcePage:%d, sourceDoc:%@)>", NSStringFromClass([self class]), self.type, NSStringFromCGRect(pdfRectangle_), self.pageLinkTarget, self.siteLinkTarget, self.URL, self.page, self.document.title];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (BOOL)isOverlayAnnotation {
    return self.type >= PSPDFAnnotationTypeVideo;
}

- (CGRect)rectForPageRect:(CGRect)pageRect {
    PSPDFPageInfo *pageInfo = [self.document pageInfoForPage:self.page];
    CGPoint pt1 = [PSPDFTilingView convertPDFPointToViewPoint:self.pdfRectangle.origin rect:pageInfo.pageRect rotation:pageInfo.pageRotation pageRect:pageRect];
    CGPoint pt2 = CGPointMake(self.pdfRectangle.origin.x + self.pdfRectangle.size.width, 
                              self.pdfRectangle.origin.y + self.pdfRectangle.size.height);
    pt2 = [PSPDFTilingView convertPDFPointToViewPoint:pt2 rect:pageInfo.pageRect rotation:pageInfo.pageRotation pageRect:pageRect];
    
    CGRect rect = CGRectMake(pt1.x, pt1.y, pt2.x - pt1.x, pt2.y - pt1.y);
    
    // normalize rect (pdf rects may have negative height)
    if (rect.size.height < 0) {
        rect.size.height *= -1;
        rect.origin.y -= rect.size.height;
    }
    
    if (rect.size.width < 0) {
        rect.size.width *= -1;
        rect.origin.x -= rect.size.width;
    }
    
    return rect;
}

- (BOOL)hitTest:(CGPoint)point {
    if ((pdfRectangle_.origin.x <= point.x) &&
        (pdfRectangle_.origin.y <= point.y) &&
        (point.x <= pdfRectangle_.origin.x + pdfRectangle_.size.width) &&
        (point.y <= pdfRectangle_.origin.y + pdfRectangle_.size.height)) {
        return YES;
    } else {
        return NO;
    }
}

- (void)setSiteLinkTarget:(NSString *)siteLinkTarget {
    if (siteLinkTarget != siteLinkTarget_) {
        siteLinkTarget_ = siteLinkTarget;
        
        // pre-set to web url, this may change if a pspdfkit url is detected
        self.type = PSPDFAnnotationTypeWebUrl;
    }
}

- (NSString *)uid {
    NSString *uid = [NSString stringWithFormat:@"%d_%@", self.type, NSStringFromCGRect(pdfRectangle_)];
    return uid;
}

- (BOOL)isModal {
    BOOL modal = [[options_ objectForKey:@"modal"] boolValue];
    return modal;
}

- (void)setModal:(BOOL)modal {
    NSMutableDictionary *newOptions = options_ ? [options_ mutableCopy] : [NSMutableDictionary dictionaryWithCapacity:1];
    [newOptions setObject:[NSNumber numberWithBool:modal] forKey:@"modal"];
}

- (CGSize)size {
    CGSize size = CGSizeZero;
    if ([[options_ objectForKey:@"size"] isKindOfClass:[NSString class]]) {
        NSString *sizeString = [options_ objectForKey:@"size"];
        NSArray *parts = [sizeString componentsSeparatedByString:@"x"];
        if ([parts count] == 2) {
            size = CGSizeMake([[parts objectAtIndex:0] floatValue], [[parts objectAtIndex:1] floatValue]);
        }
    }
    return size;
}

- (void)setSize:(CGSize)size {
    NSMutableDictionary *newOptions = options_ ? [options_ mutableCopy] : [NSMutableDictionary dictionaryWithCapacity:1];
    NSString *sizeString = [NSString stringWithFormat:@"%fx%f", size.width, size.height];
    [newOptions setObject:sizeString forKey:@"size"];
}

@end
