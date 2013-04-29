//
//  PSPDFIconGenerator.m
//  PSPDFKit
//
//  Copyright (c) 2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFIconGenerator.h"
#import "PSPDFKitGlobal.h"

@interface PSPDFIconGenerator() {
    NSMutableDictionary *imageCache_;
}
@end

@implementation PSPDFIconGenerator

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Singleton

static PSPDFIconGenerator *sharedGenerator = nil; 
+ (PSPDFIconGenerator *)sharedGenerator { 
    static dispatch_once_t pred; 
    dispatch_once(&pred, ^{ sharedGenerator = [[NSClassFromString(kPSPDFIconGeneratorClassName) alloc] init]; });
    return sharedGenerator;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if((self = [super init])) {
        imageCache_ = [[NSMutableDictionary alloc] initWithCapacity:5];
    }
    return self;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

// Generates in-code images.
- (UIImage *)iconForType:(PSPDFIconType)iconType {
    UIImage *iconImage = nil;
    @synchronized(self) {
        
        // try to access the cache
        iconImage = [imageCache_ objectForKey:[NSNumber numberWithInteger:iconType]];
        
        if (!iconImage) {
            switch (iconType) {
                case PSPDFIconTypeOutline: {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22.f, 22.f), NO, 0.0f);
                    [[UIColor whiteColor] setFill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(2, 6,   3, 3)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(2, 12,  3, 3)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(2, 18,  3, 3)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(7, 6,  17, 3)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(7, 12, 17, 3)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(7, 18, 17, 3)] fill];            
                }break;
                    
                case PSPDFIconTypePage: {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(23.f, 24.f), NO, 0.0f);
                    [[UIColor whiteColor] setStroke];
                    UIBezierPath* rectanglePath = [UIBezierPath bezierPathWithRect:CGRectMake(7, 5, 10, 14)];
                    rectanglePath.lineWidth = 2;
                    [rectanglePath stroke];
                }break;
                    
                case PSPDFIconTypeThumbnails: {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26.f, 24.f), NO, 0.0f);
                    [[UIColor whiteColor] setFill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(6,   4, 5, 6)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(14,  4, 5, 6)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(6,  13, 5, 6)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(14, 13, 5, 6)] fill];            
                }break;
                    
                case PSPDFIconTypeBackArrow: {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(27.f, 22.f), NO, 0.f);
                    CGContextRef context = UIGraphicsGetCurrentContext();
                    CGContextSetFillColor(context, CGColorGetComponents([UIColor blackColor].CGColor));
                    CGContextBeginPath(context);
                    CGContextMoveToPoint(context, 8.0f, 13.0f);
                    CGContextAddLineToPoint(context, 24.0f, 4.0f);
                    CGContextAddLineToPoint(context, 24.0f, 22.0f);
                    CGContextClosePath(context);
                    CGContextFillPath(context);
                }break;
                    
                case PSPDFIconTypeBackArrowSmall: {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20.f, 20.f), NO, 0.f);
                    CGContextRef context = UIGraphicsGetCurrentContext();
                    CGContextSetFillColor(context, CGColorGetComponents([UIColor blackColor].CGColor));
                    CGContextBeginPath(context);
                    CGContextMoveToPoint(context, 8.0f, 13.0f);
                    CGContextAddLineToPoint(context, 20.0f, 6.0f);
                    CGContextAddLineToPoint(context, 20.0f, 20.0f);
                    CGContextClosePath(context);
                    CGContextFillPath(context);
                }break;
                    
                case PSPDFIconTypeForwardArrow: {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(44.f, 44.f), NO, 0.f);
                    UIBezierPath* bezierPath = [UIBezierPath bezierPath];
                    [bezierPath moveToPoint:CGPointMake(18, 14.5)];
                    [bezierPath addLineToPoint:CGPointMake(18, 29.5)];
                    [bezierPath addLineToPoint:CGPointMake(28, 22)];
                    [bezierPath addLineToPoint:CGPointMake(18, 14.5)];
                    [bezierPath closePath];
                    [[UIColor darkGrayColor] setFill];
                    [bezierPath fill];
                }break;
                    
                case PSPDFIconTypePrint: {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20.f, 22.f), NO, 0.f);
                    [[UIColor whiteColor] setFill];
                    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 11, 20, 7) cornerRadius:1] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 3,  5, 14,  5)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 2, 12,  1,  1)] fillWithBlendMode:kCGBlendModeClear alpha:1];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 4, 12,  1,  1)] fillWithBlendMode:kCGBlendModeClear alpha:1];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 2, 15, 16,  1)] fillWithBlendMode:kCGBlendModeClear alpha:1];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 2, 16,  1,  1)] fillWithBlendMode:kCGBlendModeClear alpha:1];
                    [[UIBezierPath bezierPathWithRect:CGRectMake(17, 16,  1,  1)] fillWithBlendMode:kCGBlendModeClear alpha:1];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 3, 18, 14,  3)] fill];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 4, 17, 12,  1)] fillWithBlendMode:kCGBlendModeClear alpha:1];
                    [[UIBezierPath bezierPathWithRect:CGRectMake( 4, 19, 12,  1)] fillWithBlendMode:kCGBlendModeClear alpha:1];
                }break;
                    
                default:
                    PSPDFLogWarning(@"Unknown type: %d", iconType);
                    return nil;
            }
            
            iconImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            // save in cache
            [imageCache_ setObject:iconImage forKey:[NSNumber numberWithInteger:iconType]];
        }
    }
    return iconImage;
}

@end
