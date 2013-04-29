//
//  PSPDFTilingView+Annotations.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
// 
//  Based on code by Sorin Nistor. Many, Many thanks!
//  Copyright (c) 2011-2012 Sorin Nistor. All rights reserved. This software is provided 'as-is', without any express or implied warranty.
//  In no event will the authors be held liable for any damages arising from the use of this software.
//  Permission is granted to anyone to use this software for any purpose, including commercial applications,
//  and to alter it and redistribute it freely, subject to the following restrictions:
//  1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software.
//     If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source distribution.
//

#import "PSPDFTilingView+Annotations.h"
#import "PSPDFAnnotation.h"

@implementation PSPDFTilingView (PSPDFAnnotations)

+ (CGPoint)convertViewPointToPDFPoint:(CGPoint)viewPoint rect:(CGRect)cropBox rotation:(NSUInteger)rotation pageRect:(CGRect)pageRenderRect {
    CGPoint pdfPoint = CGPointMake(0, 0);
    
    switch (rotation) {
        case 90:
        case -270:
            pdfPoint.x = cropBox.size.width * (viewPoint.y - pageRenderRect.origin.y) / pageRenderRect.size.height;
            pdfPoint.y = cropBox.size.height * (viewPoint.x - pageRenderRect.origin.x) / pageRenderRect.size.width;
            break;
        case 180:
        case -180:
            pdfPoint.x = cropBox.size.width * (pageRenderRect.size.width - (viewPoint.x - pageRenderRect.origin.x)) / pageRenderRect.size.width;
            pdfPoint.y = cropBox.size.height * (viewPoint.y - pageRenderRect.origin.y) / pageRenderRect.size.height;
            break;
        case -90:
        case 270:
            pdfPoint.x = cropBox.size.width * (pageRenderRect.size.height - (viewPoint.y - pageRenderRect.origin.y)) / pageRenderRect.size.height;
            pdfPoint.y = cropBox.size.height * (pageRenderRect.size.width - (viewPoint.x - pageRenderRect.origin.x)) / pageRenderRect.size.width;
            break;
        case 0:
        default:
            pdfPoint.x = cropBox.size.width * (viewPoint.x - pageRenderRect.origin.x) / pageRenderRect.size.width;
            pdfPoint.y = cropBox.size.height * (pageRenderRect.size.height - (viewPoint.y - pageRenderRect.origin.y)) / pageRenderRect.size.height;
            break;
    }
    
    pdfPoint.x = pdfPoint.x + cropBox.origin.x;
    pdfPoint.y = pdfPoint.y+ cropBox.origin.y;
    
    return pdfPoint;
}

+ (CGPoint)convertPDFPointToViewPoint:(CGPoint)pdfPoint rect:(CGRect)cropBox rotation:(NSUInteger)rotation pageRect:(CGRect)pageRenderRect {
    CGPoint viewPoint = CGPointMake(0, 0);
    
    switch (rotation) {
        case 90:
        case -270:
            viewPoint.x = pageRenderRect.size.width * (pdfPoint.y - cropBox.origin.y) / cropBox.size.height;
            viewPoint.y = pageRenderRect.size.height * (pdfPoint.x - cropBox.origin.x) / cropBox.size.width;
            break;
        case 180:
        case -180:
            viewPoint.x = pageRenderRect.size.width * (cropBox.size.width - (pdfPoint.x - cropBox.origin.x)) / cropBox.size.width;
            viewPoint.y = pageRenderRect.size.height * (pdfPoint.y - cropBox.origin.y) / cropBox.size.height;
            break;
        case -90:
        case 270:
            viewPoint.x = pageRenderRect.size.width * (cropBox.size.height - (pdfPoint.y - cropBox.origin.y)) / cropBox.size.height;
            viewPoint.y = pageRenderRect.size.height * (cropBox.size.width - (pdfPoint.x - cropBox.origin.x)) / cropBox.size.width;
            break;
        case 0:
        default:
            viewPoint.x = pageRenderRect.size.width * (pdfPoint.x - cropBox.origin.x) / cropBox.size.width;
            viewPoint.y = pageRenderRect.size.height * (cropBox.size.height - (pdfPoint.y - cropBox.origin.y)) / cropBox.size.height;
            break;
    }
    
    viewPoint.x = viewPoint.x + pageRenderRect.origin.x;
    viewPoint.y = viewPoint.y + pageRenderRect.origin.y;
    
    return viewPoint;
}

@end
