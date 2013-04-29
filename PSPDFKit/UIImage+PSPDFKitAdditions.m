//
//  UIImage+PSPDFKitAdditions.m
//  PSPDFKit
//
//  Created by Matt Gemmell on 20/08/2008.
//  Heavily fixed and modified by Peter Steinberger
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//  (Copyright 2008 Instinctive Code)
//

#import "PSPDFKit.h"
#import "UIImage+PSPDFKitAdditions.h"
#include <turbojpeg.h>

PSPDF_FIX_CATEGORY_BUG(UIImagePSPDFKitAdditions)

@implementation UIImage (PSPDFKitAdditions)

- (UIImage *)pspdf_imageToFitSize:(CGSize)fitSize method:(PSPDFImageResizingMethod)resizeMethod honorScaleFactor:(BOOL)honorScaleFactor {
	float imageScaleFactor = 1.f;
    if (honorScaleFactor) {
        imageScaleFactor = [self scale];
    }
    
    float sourceWidth = [self size].width * imageScaleFactor;
    float sourceHeight = [self size].height * imageScaleFactor;
    float targetWidth = fitSize.width;
    float targetHeight = fitSize.height;
    BOOL cropping = !(resizeMethod == PSPDFImageResizeScale);
    
    // adapt rect based on source image size
    switch (self.imageOrientation) {
        case UIImageOrientationLeft:    // button top
        case UIImageOrientationRight:   // button bottom
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored: { 
            ps_swapf(sourceWidth, sourceHeight);
            ps_swapf(targetWidth, targetHeight);
        }break;
            
        case UIImageOrientationUp:     // button left
        case UIImageOrientationDown:   // button right
        default: {             // works in default
        }break;
    }
    
    // Calculate aspect ratios
    float sourceRatio = sourceWidth / sourceHeight;
    float targetRatio = targetWidth / targetHeight;
    
    // Determine what side of the source image to use for proportional scaling
    BOOL scaleWidth = (sourceRatio <= targetRatio);
    // Deal with the case of just scaling proportionally to fit, without cropping
    scaleWidth = (cropping) ? scaleWidth : !scaleWidth;
    
    // Proportionally scale source image
    CGFloat scalingFactor, scaledWidth, scaledHeight;
    if (scaleWidth) {
        scalingFactor = 1.f / sourceRatio;
        scaledWidth = targetWidth;
        scaledHeight = round(targetWidth * scalingFactor);
    } else {
        scalingFactor = sourceRatio;
        scaledWidth = round(targetHeight * scalingFactor);
        scaledHeight = targetHeight;
    }
    float scaleFactor = scaledHeight / sourceHeight;
    
    // Calculate compositing rectangles
    CGRect sourceRect, destRect;
    if (cropping) {
        destRect = CGRectMake(0, 0, targetWidth, targetHeight);
        float destX = 0, destY = 0;
        if (resizeMethod == PSPDFImageResizeCrop) {
            // Crop center
            destX = round((scaledWidth - targetWidth) / 2.f);
            destY = round((scaledHeight - targetHeight) / 2.f);
        } else if (resizeMethod == PSPDFImageResizeCropStart) {
            // Crop top or left (prefer top)
            if (scaleWidth) {
                // Crop top
                destX = 0.f;
                destY = 0.f;
            } else {
                // Crop left
                destX = 0.f;
                destY = round((scaledHeight - targetHeight) / 2.f);
            }
        } else if (resizeMethod == PSPDFImageResizeCropEnd) {
            // Crop bottom or right
            if (scaleWidth) {
                // Crop bottom
                destX = round((scaledWidth - targetWidth) / 2.f);
                destY = round(scaledHeight - targetHeight);
            } else {
                // Crop right
                destX = round(scaledWidth - targetWidth);
                destY = round((scaledHeight - targetHeight) / 2.f);
            }
        }
        sourceRect = CGRectMake(destX / scaleFactor, destY / scaleFactor,
                                targetWidth / scaleFactor, targetHeight / scaleFactor);
    } else {
        sourceRect = CGRectMake(0.f, 0.f, sourceWidth, sourceHeight);
        destRect = CGRectMake(0.f, 0.f, scaledWidth, scaledHeight);
    }
    
    // Create appropriately modified image.
    UIImage *image = nil;
    UIGraphicsBeginImageContextWithOptions(destRect.size, YES, honorScaleFactor ? 0.f : 1.f); // 0.0f for scale means "correct scale for device's main screen".
    CGImageRef sourceImg = CGImageCreateWithImageInRect([self CGImage], sourceRect); // cropping happens here.
    image = [UIImage imageWithCGImage:sourceImg scale:0.f orientation:self.imageOrientation]; //  create cropped UIImage.
    //PSELog(@"image size: %@", NSStringFromCGSize(image.size));
    [image drawInRect:destRect]; // the actual scaling happens here, and orientation is taken care of automatically.
    CGImageRelease(sourceImg);
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

+ (UIImage*)pspdf_imageWithContentsOfResolutionIndependentFile:(NSString *)path {
    return [[UIImage alloc] initWithContentsOfResolutionIndependentFile_pspdf:path];
}

- (id)initWithContentsOfResolutionIndependentFile_pspdf:(NSString *)path {
    if ((int)[[UIScreen mainScreen] scale] == 2.f) {
        NSString *path2x = [[path stringByDeletingLastPathComponent]
                            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x.%@",
                                                            [[path lastPathComponent] stringByDeletingPathExtension],
                                                            [path pathExtension]]];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:path2x]) {
            return [self initWithContentsOfFile:path2x];
        }
    }
    
    return [self initWithContentsOfFile:path];
}

static CGColorSpaceRef colorSpace;
__attribute__((constructor)) static void initialize_colorSpace() {
    colorSpace = CGColorSpaceCreateDeviceRGB();
}
__attribute__((destructor)) static void destroy_colorSpace() {
    CFRelease(colorSpace);
}

// advanced trickery: http://stackoverflow.com/questions/5266272/non-lazy-image-loading-in-ios
+ (UIImage *)pspdf_preloadedImageWithContentsOfFile:(NSString *)path {
    
    // this *really* loads the image (imageWithContentsOfFile is lazy)
    CGImageRef image = NULL;
    CGDataProviderRef dataProvider = CGDataProviderCreateWithFilename([path cStringUsingEncoding:NSUTF8StringEncoding]);
    if (!dataProvider) {
        PSPDFLogWarning(@"Could not open %@!", path);
        return nil;
    }
    
    if ([path hasSuffix:@"jpg"]) {
        image = CGImageCreateWithJPEGDataProvider(dataProvider, NULL, false, kCGRenderingIntentDefault);
    }else {
        image = CGImageCreateWithPNGDataProvider(dataProvider, NULL, false, kCGRenderingIntentDefault);
    }
    CGDataProviderRelease(dataProvider);
    
    // make a bitmap context of a suitable size to draw to, forcing decode
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    
    CGContextRef imageContext =  CGBitmapContextCreate(NULL, width, height, 8, width*4, colorSpace, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Little);
    
    // draw the image to the context, release it
    CGContextDrawImage(imageContext, CGRectMake(0.f, 0.f, width, height), image);
    CGImageRelease(image);
    
    // now get an image ref from the context
    CGImageRef outputImage = CGBitmapContextCreateImage(imageContext);
    UIImage *cachedImage = [UIImage imageWithCGImage:outputImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    
    // clean up
    CGImageRelease(outputImage);
    CGContextRelease(imageContext);
    return cachedImage;
}

- (UIImage *)pspdf_preloadedImage {
    CGImageRef image = self.CGImage;
    
    // make a bitmap context of a suitable size to draw to, forcing decode
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    
    CGContextRef imageContext =  CGBitmapContextCreate(NULL, width, height, 8, width*4, colorSpace, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Little);
    
    // draw the image to the context, release it
    CGContextDrawImage(imageContext, CGRectMake(0, 0, width, height), image);
    
    // now get an image ref from the context
    CGImageRef outputImage = CGBitmapContextCreateImage(imageContext);
    UIImage *cachedImage = [UIImage imageWithCGImage:outputImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    
    // clean up
    CGImageRelease(outputImage);
    CGContextRelease(imageContext);
    return cachedImage;
}

+ (CGFloat)pspdf_scaleForImageSize:(CGSize)imageSize bounds:(CGSize)boundsSize {    
    // don't calculate if imageSize is nil
    if (CGSizeEqualToSize(imageSize, CGSizeZero)) {
        return 1.0;
    }
    
    // set up our content size and min/max zoomscale
    CGFloat xScale = boundsSize.width / imageSize.width;    // the scale needed to perfectly fit the image width-wise
    CGFloat yScale = boundsSize.height / imageSize.height;  // the scale needed to perfectly fit the image height-wise
    CGFloat minScale = MIN(xScale, yScale);                 // use minimum of these to allow the image to become fully visible
    
    // on high resolution screens we have double the pixel density, so we will be seeing every pixel if we limit the
    // maximum zoom scale to 0.5.
    CGFloat maxScale = 2.0 / [[UIScreen mainScreen] scale];
    
    // don't let minScale exceed maxScale.
    if (minScale > maxScale) {
        minScale = maxScale;
    }
    
    if (minScale > 10.0) {
        PSPDFLogWarning(@"Ridiculous high scale detected, limiting.");
        minScale = 10.0;
    }
    
    return minScale;
}

+ (UIImage *)pspdf_imageNamed:(NSString *)imageName bundle:(NSString *)bundleName {
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString *bundlePath = [resourcePath stringByAppendingPathComponent:bundleName];
    NSString *imagePath = [bundlePath stringByAppendingPathComponent:imageName];
    return [UIImage pspdf_imageWithContentsOfResolutionIndependentFile:imagePath];
}

void ReleaseJPEGBuffer(void *info, const void *data, size_t size);
void ReleaseJPEGBuffer(void *info, const void *data, size_t size) {
    tjFree((void *)data);
}

+ (UIImage *)pspdf_preloadedImageWithContentsOfFile:(NSString *)imagePath useJPGTurbo:(BOOL)useJPGTurbo {
    UIImage *cacheImage = nil;

    if (useJPGTurbo) {
        // load the file
        NSData *data = [NSData dataWithContentsOfFile:imagePath];
        unsigned char *jpegBuf = (unsigned char *)[data bytes];
        unsigned char *destBuf = nil;
        unsigned long jpegSize = [data length];
        int jwidth, jheight, jpegSubsamp;
        tjhandle decompressor = tjInitDecompress(); // cannot be shared with other threads

        // get header data
        BOOL failed = tjDecompressHeader2(decompressor, jpegBuf, jpegSize, &jwidth, &jheight, &jpegSubsamp);

        if (!failed) {
            // calculate pixels
            static const size_t bitsPerPixel = 4;
            static const size_t bitsPerComponent = 8;
            unsigned rowBytes = 4 * jwidth;
            unsigned long destBugLength = rowBytes * jheight;

            // allocate memory and decompress
            destBuf = tjAlloc(destBugLength);
            failed = tjDecompress2(decompressor, jpegBuf, jpegSize, destBuf, jwidth, jwidth * bitsPerPixel, jheight, TJPF_ABGR, 0);
            tjDestroy(decompressor);

            // transfer bytes to something UIKit can work with
            if (!failed) {
                CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, destBuf, rowBytes * jheight, ReleaseJPEGBuffer);
                CGImageRef cgImage = CGImageCreate(jwidth, jheight, bitsPerComponent, bitsPerComponent*bitsPerPixel, rowBytes, colorSpace, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Little, dataProvider, NULL, false, kCGRenderingIntentDefault);
                cacheImage = [[UIImage alloc] initWithCGImage:cgImage scale:0.0 orientation:UIImageOrientationUp];

                // cleanup
                CFRelease(dataProvider);
                CGImageRelease(cgImage);
            }
        }
    }else {
        cacheImage = [UIImage pspdf_preloadedImageWithContentsOfFile:imagePath];
    }

    return cacheImage;
}

@end
