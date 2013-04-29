//
//  PSPDFKitGlobal.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKitGlobal.h"
#import "PSPDFKit.h"
#import "PSPDFPatches.h"
#import "InfoPlist.h" // defines the version string

// draw demo mode code
#ifdef kPSPDFKitDemoMode
inline void DrawPSPDFKit(CGContextRef context) {
    char *text = "PSPDFKit DEMO"; \
    CGFloat demoPosition = PSIsIpad() ? 50.f : 20.f;
    NSUInteger fontSize = PSIsIpad() ? 30 : 14; \
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor); \
    CGContextSelectFont(context, "Helvetica-Bold", fontSize, kCGEncodingMacRoman); \
    CGAffineTransform xform = CGAffineTransformMake(1.0, 0.0, 0.0, -1.0, 0.0, 0.0); \
    CGContextSetTextMatrix(context, xform); \
    CGContextSetTextDrawingMode(context, kCGTextFill); \
    CGContextSetTextPosition(context, demoPosition, demoPosition + round(fontSize / 4.0f)); \
    CGContextShowText(context, text, (text[0] == 'P') ? 13 : 99999); // be nasty, in case text gets deleted strlen(text)
}
#else
inline void DrawPSPDFKit(CGContextRef context) {}
#endif

// global variables
NSString *const kPSPDFErrorDomain = @"com.pspdfkit.error";
PSPDFLogLevel kPSPDFLogLevel = PSPDFLogLevelWarning;
PSPDFAnimate kPSPDFAnimateOption = PSPDFAnimateModernDevices;
CGFloat kPSPDFKitPDFAnimationDuration = 0.1f;
CGFloat kPSPDFKitHUDTransparency = 0.7f;
CGFloat kPSPDFInitialAnnotationLoadDelay = 0.2f;
NSUInteger kPSPDFKitZoomLevels = 0; // late-init
BOOL kPSPDFKitDebugScrollViews = NO;
BOOL kPSPDFKitDebugMemory = NO;
NSString *kPSPDFCacheClassName = @"PSPDFCache";
NSString *kPSPDFIconGeneratorClassName = @"PSPDFIconGenerator";

extern void PSPDFKitInitializeGlobals(void) {
    if (kPSPDFKitZoomLevels == 0) {
        kPSPDFKitZoomLevels = PSPDFIsCrappyDevice() ? 4 : 5;
    }
    
    // apply UIKit-Patch for iOS5 for UIPageViewController
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PSPDF_IF_IOS5_OR_GREATER(pspdf_patchUIKit();)
    });
}

BOOL PSPDFShouldAnimate(void) {
    BOOL shouldAnimate = (!PSPDFIsCrappyDevice() && kPSPDFAnimateOption == PSPDFAnimateModernDevices) || kPSPDFAnimateOption == PSPDFAnimateEverywhere;
    return shouldAnimate;
}

CGSize PSPDFSizeForScale(CGRect rect, CGFloat scale) {
	CGSize size = CGSizeMake(roundf(rect.size.width*scale), roundf(rect.size.height*scale));
    return size;
}

BOOL PSPDFIsCrappyDevice(void) {
    static BOOL isCrappyDevice = YES;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL isSimulator = NO;
        BOOL isIPad2 = (PSIsIpad() && [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]);
        BOOL hasRetina = [[UIScreen mainScreen] scale] > 1.f;
      
// enable animations on simulator
#if TARGET_IPHONE_SIMULATOR
        isSimulator = YES;
#endif
        if (isIPad2 || hasRetina || isSimulator) {
            isCrappyDevice = NO;
        }else {
            PSPDFLog(@"Old device detected. Reducing animations.");
        }
    });
    
    return isCrappyDevice;
}

extern NSString *PSPDFVersionString(void) {
    return GIT_VERSION;
}

// for localization
#define kPSPDFKitBundleName @"PSPDFKit.bundle"
NSBundle *pspdfkitBundle(void);
NSBundle *pspdfkitBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:kPSPDFKitBundleName];
        bundle = [NSBundle bundleWithPath:path];
    });
    return bundle;
}

static NSString *preferredLocale(void);
static NSString *preferredLocale(void) {
    static NSString *locale = nil;
    if (!locale) {
        NSArray *locales = [NSLocale preferredLanguages];
        if ([locales count]) {
            locale = [[locales objectAtIndex:0] copy];
        }else {
            PSPDFLogWarning(@"No preferred language? [NSLocale preferredLanguages] returned nil. Defaulting to english.");
            locale = [[NSString alloc] initWithString:@"en"];
        }
    }
    return locale;
}

static NSDictionary *localizationDict_ = nil;
NSString *PSPDFLocalize(NSString *stringToken) {
    // load language from bundle
    NSString *localization = NSLocalizedStringFromTableInBundle(stringToken, @"PSPDFKit", pspdfkitBundle(), @"");
    if (!localization) {
        localization = stringToken;
    }
    
    // try loading from the global translation dict
    NSString *replLocale = nil;
    if (localizationDict_) {
        NSString *language = preferredLocale();
        replLocale = [[localizationDict_ objectForKey:language] objectForKey:stringToken];
        if (!replLocale && ![localizationDict_ objectForKey:language] && ![language isEqualToString:@"en"]) {
            replLocale = [[localizationDict_ objectForKey:@"en"] objectForKey:stringToken];
        }
    }
    
    return replLocale ? replLocale : localization;
}

extern void PSPDFSetLocalizationDictionary(NSDictionary *localizationDict) {
    if (localizationDict != localizationDict_) {
        localizationDict_ = [localizationDict copy];
    }
    
    PSPDFLog(@"new localization dictionary set. locale: %@; dict: %@", preferredLocale(), localizationDict);
}
