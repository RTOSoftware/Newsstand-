//
//  PSPDFPageInfo.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFPageInfo.h"
#import "PSPDFKitGlobal.h"

@implementation PSPDFPageInfo

@synthesize pageRect = pageRect_;
@synthesize pageRotation = pageRotation_;
@synthesize page = page_;
@synthesize document = document_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - static

+ (id)pageInfoWithRect:(CGRect)rect rotation:(NSUInteger)rotation {
    PSPDFPageInfo *pageInfo = [[[self class] alloc] initWithRect:rect rotation:rotation];
    return pageInfo;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithRect:(CGRect)rect rotation:(NSUInteger)rotation {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        pageRect_ = rect;
        pageRotation_ = rotation;
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<PSPDFPageInfo rect:%@ rotation:%d>", NSStringFromCGRect(self.pageRect), self.pageRotation];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (CGRect)rotatedPageRect {
    int pageRotation = self.pageRotation;
    CGRect rect = self.pageRect;
    
    if ((pageRotation == 0) || (pageRotation == 180) || (pageRotation == -180)) {
        // noop
    }else {
        CGFloat tmp = rect.size.width;
        rect.size.width = rect.size.height;
        rect.size.height = tmp;
    }
    
    rect = PSRectClearCoords(rect); // we only want the size
    return rect;
}

@end


@implementation PSPDFPageCoordinates

@synthesize pdfPoint = pdfPoint_;
@synthesize screenPoint = screenPoint_;
@synthesize viewPoint = viewPoint_;
@synthesize pageSize = pageSize_;
@synthesize zoomScale = zoomScale_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - static

+ (id)pageCoordinatesWithpdfPoint:(CGPoint)pdfPoint screenPoint:(CGPoint)screenPoint viewPoint:(CGPoint)viewPoint pageSize:(CGSize)pageSize zoomScale:(CGFloat)zoomScale {
    PSPDFPageCoordinates *coordinates = [[[self class] alloc] initCoordinatesWithpdfPoint:pdfPoint screenPoint:screenPoint viewPoint:viewPoint pageSize:(CGSize)pageSize zoomScale:zoomScale];
    return coordinates;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Object

- (id)initCoordinatesWithpdfPoint:(CGPoint)pdfPoint screenPoint:(CGPoint)screenPoint viewPoint:(CGPoint)viewPoint pageSize:(CGSize)pageSize zoomScale:(CGFloat)zoomScale {
    if ((self = [super init])) {
        pdfPoint_ = pdfPoint;
        screenPoint_ = screenPoint;
        viewPoint_ = viewPoint;
        pageSize_ = pageSize;
        zoomScale_ = zoomScale;
    }
    return self;
}

- (NSString *)description {
    NSString *description = [NSString stringWithFormat:@"<PSPDFPageCoordinates pdfPoint:%@ screenPoint:%@ viewPoint:%@ pageSize:%@ zoomScale:%d>", NSStringFromCGPoint(pdfPoint_), NSStringFromCGPoint(screenPoint_), NSStringFromCGPoint(viewPoint_), NSStringFromCGSize(pageSize_), zoomScale_];
    return description;
}

@end
