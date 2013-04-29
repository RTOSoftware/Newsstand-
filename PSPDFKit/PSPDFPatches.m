//
//  PSPDFPatches.m
//  PSPDFKit
//
//  Copyright (c) 2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFPatches.h"
#import "PSPDFKitGlobal.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#if __has_feature(objc_arc)
#error "Compile this file without ARC"
#endif

void pspdf_swizzle(Class c, SEL orig, SEL new) {
    Method origMethod = class_getInstanceMethod(c, orig);
    Method newMethod = class_getInstanceMethod(c, new);
    if(class_addMethod(c, orig, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(c, new, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    }else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

// To use the pageCurl feature, we have to apply several fixes to Apple's UIPageViewController, as this class is new and still relatively buggy.
// Strictly speaking this is private API, so if you're afraid of it, just set the preprocessor define _PSPDFKIT_DONT_USE_OBFUSCATED_PRIVATE_API_.
// If you disable this, the pageCurl feature will be disabled and the framework falls back to scrolling.
//
// I'd wish those hacks were not neccessary, but I'm pragmatic and like to use stuff and not wait for iOS6 to hopefully fix this.

#ifndef _PSPDFKIT_DONT_USE_OBFUSCATED_PRIVATE_API_

UIWindow *pspdf_keyWindow(void);
UIWindow *pspdf_keyWindow(void) {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        SEL isRotationDisabledSelector = NSSelectorFromString([NSString stringWithFormat:@"isInterfa%@sabled", @"ceAutorotationDi"]);
        if ([window respondsToSelector:isRotationDisabledSelector]) {
            return window;
        }
    }
    return nil;
}

BOOL pspdf_isRotationDisabled(void);
BOOL pspdf_isRotationDisabled(void) {
    static NSInvocation *invocation;
    static dispatch_once_t onceToken;
    static SEL isRotationDisabledSelector;
    dispatch_once(&onceToken, ^{
        isRotationDisabledSelector = NSSelectorFromString([NSString stringWithFormat:@"isInterfa%@sabled", @"ceAutorotationDi"]);
        NSMethodSignature *signature = [UIWindow instanceMethodSignatureForSelector:isRotationDisabledSelector];
        invocation = [[NSInvocation invocationWithMethodSignature:signature] retain];
        [invocation setSelector:isRotationDisabledSelector];
    });
    BOOL isRotationDisabled = NO; // isInterfaceAutorotationDisabled
    UIWindow *window = pspdf_keyWindow();
    if ([window respondsToSelector:isRotationDisabledSelector]) {
        [invocation setTarget:window];
        [invocation invoke];
        [invocation getReturnValue:&isRotationDisabled];
    }
    return isRotationDisabled;
}

void pspdf_beginDisableIfcAutorotation(id this, SEL this_cmd);
void pspdf_beginDisableIfcAutorotation(id this, SEL this_cmd) {
    if (!pspdf_isRotationDisabled()) {
        SEL beginSelector = NSSelectorFromString(@"pspdf_beginDisableIfcAutorotation");
        UIWindow *window = pspdf_keyWindow();
        if ([window respondsToSelector:beginSelector]) {
            [window performSelector:beginSelector];
        }
    }
}

void pspdf_endDisableIfcAutorotation(id this, SEL this_cmd);
void pspdf_endDisableIfcAutorotation(id this, SEL this_cmd) {
    if (pspdf_isRotationDisabled()) {
        SEL endSelector = NSSelectorFromString(@"pspdf_endDisableIfcAutorotation");
        UIWindow *window = pspdf_keyWindow();
        if ([window respondsToSelector:endSelector]) {
            [window performSelector:endSelector];
        }
    }
}

// primary reason why we can't use ARC here.
void pspdf_customDealloc(id this, SEL this_cmd);
void pspdf_customDealloc(id this, SEL this_cmd) {    
    __block id weakThis = this;
    double delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        [weakThis performSelector:NSSelectorFromString(@"pspdf_customDealloc")];
    });
}

void pspdf_patchUIKit(void) {
    
    // no need to patch this on iOS4, those classes don't yet exist there.
    PSPDF_IF_IOS5_OR_GREATER(
                             // _UIPageCurlState message sent to deallocated instance
                             Class pagecurlstate = NSClassFromString([NSString stringWithFormat:@"_%@Cu%@ate", @"UIPage", @"rlSt"]);
                             SEL customDealloc = NSSelectorFromString(@"pspdf_customDealloc");
                             if(pagecurlstate) {
                                 class_addMethod(pagecurlstate, customDealloc, (IMP)pspdf_customDealloc, "");
                                 pspdf_swizzle(pagecurlstate, NSSelectorFromString(@"dealloc"), customDealloc);
                             }
                             
                             // [_UIPageCurl _pageCurlAnimationDidStop:withState:]: message sent to deallocated instance 0x14a03fe0
                             Class pagecurl = NSClassFromString([NSString stringWithFormat:@"_%@Cu%@", @"UIPage", @"rl"]);
                             if(pagecurl) {
                                 class_addMethod(pagecurl, customDealloc, (IMP)pspdf_customDealloc, "");
                                 pspdf_swizzle(pagecurl, NSSelectorFromString(@"dealloc"), customDealloc);
                             }
                             
                             // prevent warnings like [UIWindow endDisablingInterfaceAutorotationAnimated:] called on <UIWindow: 0x57a980; frame = (0 0; 768 1024); layer = <UIWindowLayer: 0x57aa70>> without matching -beginDisablingInterfaceAutorotation. Ignoring.
                             
                             // If you think here "what the f*ck", you're correct. I _could_ skip this, but then the log gets polluted with above log messages
                             // Because UIPageViewController messes up so bad.
                             
                             SEL beginAuto = NSSelectorFromString(@"pspdf_beginDisableIfcAutorotation");
                             class_addMethod([UIWindow class], beginAuto, (IMP)pspdf_beginDisableIfcAutorotation, "");
                             SEL beginDisableSel = NSSelectorFromString([NSString stringWithFormat:@"beginDis%@orotation", @"ablingInterfaceAut"]);
                             if(beginDisableSel) {
                                 pspdf_swizzle([UIWindow class], beginDisableSel, beginAuto);
                             }
                             SEL endAuto = NSSelectorFromString(@"pspdf_endDisableIfcAutorotation");
                             class_addMethod([UIWindow class], endAuto, (IMP)pspdf_endDisableIfcAutorotation, "");
                             SEL endAutoOrig = NSSelectorFromString([NSString stringWithFormat:@"endDis%@orotation", @"ablingInterfaceAut"]);
                             if(endAutoOrig) {
                                 pspdf_swizzle([UIWindow class], endAutoOrig, endAuto);    
                             }
                             )
}

#else
void pspdf_patchUIKit(void) {}
#endif
