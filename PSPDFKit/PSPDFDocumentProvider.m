//
//  PSPDFDocumentProvider.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFDocumentProvider.h"
#import "PSPDFGlobalLock.h"
#import "PSPDFKitGlobal.h"

@interface PSPDFDocumentProvider() {
    NSUInteger documentRefRetainCount_;
    CGPDFDocumentRef documentRef_;
    NSMutableDictionary *openPages_;
}
@end

@implementation PSPDFDocumentProvider

@synthesize URL = URL_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithDocumentRef:(CGPDFDocumentRef)documentRef URL:(NSURL *)URL {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        documentRefRetainCount_ = 0;
        URL_ = URL;
        documentRef_ = CGPDFDocumentRetain(documentRef);
        openPages_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    NSAssert([openPages_ count] == 0, @"There are open pages. You forgot calling releasePageRef: %@", self);
    PSPDFDeregisterObject(self);
    
    // deallocating the document can be slow; make sure we use the background thread for it.
    if ([NSThread mainThread]) {
        CGPDFDocumentRef documentRef = documentRef_;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            CGPDFDocumentRelease(documentRef);
        });    
    }else {
        CGPDFDocumentRelease(documentRef_);        
    }
}

- (NSString *)description {
    NSString *description = [NSString stringWithFormat:@"<PSPDFDocumentProvider for %@ - open pages: %@>", documentRef_, openPages_];
    return description;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (CGPDFDocumentRef)requestDocumentRef {
    documentRefRetainCount_++;
    return documentRef_;
}

- (void)releaseDocumentRef:(CGPDFDocumentRef)documentRef {
    NSAssert(documentRefRetainCount_ > 0, @"Document retain count is empty?");
    NSAssert(documentRef == documentRef_, @"DocumentRef must be the same that's saved internally!");
    documentRefRetainCount_--;
}

/// Requests a page for the current loaded document. Needs to be returned in releasePageRef.
- (CGPDFPageRef)requestPageRefForPage:(NSUInteger)page {
    if (documentRef_ == nil) {
        PSPDFLogWarning(@"Document reference is nil!");
        return nil;
    }
    
#ifndef __clang_analyzer__
    CGPDFPageRef pageRef = (__bridge CGPDFPageRef)[openPages_ objectForKey:[NSNumber numberWithInteger:page]];
#endif
    if (!pageRef) {
        pageRef = CGPDFDocumentGetPage(documentRef_, page);
        if (!pageRef) {
            PSPDFLogWarning(@"Error while getting pageRef for page %d", page);
        }else {
            CGPDFPageRetain(pageRef);
            [openPages_ setObject:(__bridge id)pageRef forKey:[NSNumber numberWithInteger:page]];
        }
    }
    
    return pageRef;
}

/// Releases a page reference. 
- (void)releasePageRef:(CGPDFPageRef)pageRef {
    if (!pageRef) {
        PSPDFLogWarning(@"Tried to clear nil pageRef reference.");
        return;
    }
    
    NSUInteger pageNumber = (NSUInteger)CGPDFPageGetPageNumber(pageRef);
    NSAssert([openPages_ objectForKey:[NSNumber numberWithInteger:pageNumber]] != nil, @"Page Number is not tracked?");
    [openPages_ removeObjectForKey:[NSNumber numberWithInteger:pageNumber]];
    CGPDFPageRelease(pageRef);
}

@end
