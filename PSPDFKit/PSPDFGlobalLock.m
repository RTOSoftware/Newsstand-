//
//  PSPDFGlobalLock.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFGlobalLock.h"
#import "PSPDFDocumentProvider.h"
#import <libkern/OSAtomic.h>

@interface PSPDFGlobalLock() {
    CGPDFPageRef      pdfPage_;
    CGPDFDocumentRef  pdfDocument_;
    NSString         *pdfPassword_;
    NSLock           *pdfGlobalLock_;
    OSSpinLock        cacheAccessLock_;
    NSInteger         fileIndex_;
    NSUInteger        documentHash_;
}
@property(nonatomic, assign, getter=isClearCacheRequested) BOOL clearCacheRequested;
@property(nonatomic, assign) NSInteger page;
@end

@implementation PSPDFGlobalLock

@synthesize clearCacheRequested = clearCacheRequested_;
@synthesize page = page_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Static

static PSPDFGlobalLock *sharedPSPDFGlobalLock = nil; 
+ (PSPDFGlobalLock *)sharedPSPDFGlobalLock { 
    static dispatch_once_t pred; 
    dispatch_once(&pred, ^{ sharedPSPDFGlobalLock = [[PSPDFGlobalLock alloc] init]; });
    return sharedPSPDFGlobalLock;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (void)clearCacheNoLock:(BOOL)forced {
    if (self.isClearCacheRequested || forced) {
        if (!forced) {
            PSPDFLog(@"Clear Cache was requested.");
        }
        CGPDFPageRelease(pdfPage_);
        pdfPage_ = nil;
        self.page = -1; // invalidate page
        CGPDFDocumentRelease(pdfDocument_);
        pdfDocument_ = nil;
        pdfPassword_ = nil;
        fileIndex_ = -1;
        documentHash_ = 0;
        clearCacheRequested_ = NO;
    } 
}

// internal - do not call from outside
- (void)clearCache:(BOOL)forced {
    OSSpinLockLock(&cacheAccessLock_);
    [self clearCacheNoLock:forced];
    OSSpinLockUnlock(&cacheAccessLock_);
}

// only enter after locking state! page = logical page (starts with 0)
- (CGPDFDocumentRef)openPDFDocument:(PSPDFDocument *)document page:(NSUInteger)page {
    [self clearCache:NO];
    
    // do we have to open the document?
    OSSpinLockLock(&cacheAccessLock_);
    NSInteger fileIndex = [document fileIndexForPage:page];
    NSURL *pdfPath = [document URLForFileIndex:fileIndex];
    BOOL isPathEqual = documentHash_ && documentHash_ == [document hash] && fileIndex_ == fileIndex;
    BOOL isPasswordEqual = [pdfPassword_ isEqual:document.password];
    if (!isPathEqual || !pdfDocument_ || !isPasswordEqual) {
        PSPDFLogVerbose(@"pdf open, new path: %@. clearing cache now.", pdfPath);
        [self clearCacheNoLock:YES]; // force clear all!
        if (pdfPath) {
            pdfDocument_ = CGPDFDocumentCreateWithURL((__bridge CFURLRef)pdfPath);
        }else if(document.data) {
            CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)document.data);
            pdfDocument_ = CGPDFDocumentCreateWithProvider(dataProvider);
            CGDataProviderRelease(dataProvider);
        }else {
            PSPDFLogError(@"PdfPath and data is nil.");
            return nil;
        }
        
        // try to unlock it with a password
        pdfPassword_ = document.password;
        if (pdfDocument_ && document.password) {
            CGPDFDocumentUnlockWithPassword(pdfDocument_, [document.password cStringUsingEncoding:NSASCIIStringEncoding]);
        }
    }
    OSSpinLockUnlock(&cacheAccessLock_);
    
    if (!pdfDocument_) {
        PSPDFLogError(@"pdf document reference could not be aquired for %@", pdfPath);
        [pdfGlobalLock_ unlock];
    }
    
    return pdfDocument_;
}

// only enter after locking state!
- (CGPDFPageRef)openPDFWithDocument:(PSPDFDocument *)document page:(NSUInteger)page error:(NSError **)error {
    NSInteger fileIndex = [document fileIndexForPage:page];
    NSURL *pdfPath = [document URLForFileIndex:fileIndex];
    NSUInteger pdfPageNumber = [document pageNumberForPage:page];
    PSPDFLogVerbose(@"path: %@, page:%d", pdfPath, pdfPageNumber);
    [self openPDFDocument:document page:page];
    OSSpinLockLock(&cacheAccessLock_);
    if (pdfDocument_) {
        BOOL isPageEqual = page_ == pdfPageNumber;
        // same path? same page?
        if (!isPageEqual || !pdfPage_) {
            CGPDFPageRelease(pdfPage_);
            pdfPage_ = CGPDFPageRetain(CGPDFDocumentGetPage(pdfDocument_, pdfPageNumber)); // pdf starts at page 1
            fileIndex_ = fileIndex;
            documentHash_ = [document hash];
            self.page = pdfPageNumber;
        }
        
        if (!pdfPage_) {
            PSPDFLogError(@"pdf page reference could not be aquired for %@, page %d (Maybe the PDF is corrupted, locked or just doesn't exist)", [pdfPath absoluteString], page);
            
            if(error) {
                NSDictionary *errorDict = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Failed to open the pdf %@, page %d. (Maybe the PDF is corrupted, locked or just doesn't exist)", [pdfPath absoluteString], page] forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:kPSPDFErrorDomain code:PSPDFErrorCodeUnableToOpenPDF userInfo:errorDict];
            }
            
            [pdfGlobalLock_ unlock];
        }
    }else {
        PSPDFLogError(@"As pdfDocument is nil, aquiring pageRef failed.");
    }
    OSSpinLockUnlock(&cacheAccessLock_);
    
    return pdfPage_;
}

- (void)requestClearCache {
    // on old devices, wait. they can't deal with the memory pressure
    BOOL shouldWait = PSPDFIsCrappyDevice();
    [self requestClearCacheAndWait:shouldWait];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if ((self = [super init])) {
        pdfGlobalLock_ = [[NSLock alloc] init];
        NSNotificationCenter *dnc = [NSNotificationCenter defaultCenter];
        [dnc addObserver:self selector:@selector(requestClearCache) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self clearCache:YES];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)requestClearCacheAndWait:(BOOL)waitFlag {
    BOOL allowedToClearCache = NO;
    
    // try lock if waiting is set to NO
    if (!waitFlag) {
        if(![pdfGlobalLock_ tryLock]) {
            PSPDFLogVerbose(@"currently locked, requesting clear later!");
            clearCacheRequested_ = YES;
        }else {
            allowedToClearCache = YES;
        }
    }else {
        // really wait
        PSPDFLogVerbose(@"waiting for clearcache...");
        [pdfGlobalLock_ lock];
        allowedToClearCache = YES;
    }
    
    if (allowedToClearCache) {
        PSPDFLogVerbose(@"clearing internal pdf cache now!");
        [self clearCache:YES];
        [pdfGlobalLock_ unlock];
    }
}

- (CGPDFPageRef)tryLockWithDocument:(PSPDFDocument *)document page:(NSUInteger)page error:(NSError **)error; {
    BOOL isLocked = [pdfGlobalLock_ tryLock];
    if (isLocked) {
        PSPDFLogVerbose(@"tryLock successful");
        CGPDFPageRef pageRef = [self openPDFWithDocument:document page:page error:error];
        return pageRef;
    }else {
        PSPDFLogVerbose(@"tryLock failed to aquire lock");
        return nil;
    }
}

- (CGPDFPageRef)lockWithDocument:(PSPDFDocument *)document page:(NSUInteger)page error:(NSError **)error;{
    [pdfGlobalLock_ lock];
    return [self openPDFWithDocument:document page:page error:error];
}

- (PSPDFDocumentProvider *)documentProviderForDocument:(PSPDFDocument *)document page:(NSUInteger)page {
    // chances are good that we alread have the document in cache!
    OSSpinLockLock(&cacheAccessLock_);
    NSInteger fileIndex = [document fileIndexForPage:page];
    NSURL *pdfPath = [document URLForFileIndex:fileIndex];
    CGPDFDocumentRef documentRef = nil;
    BOOL trySaveInCache = NO;
    if (documentHash_ && documentHash_ == [document hash] && fileIndex == fileIndex_ && pdfDocument_) {
        documentRef = CGPDFDocumentRetain(pdfDocument_);
    }else {
        if (pdfPath) {
            documentRef = CGPDFDocumentCreateWithURL((__bridge CFURLRef)pdfPath);
        }else if(document.data) {
            CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)document.data);
            documentRef = CGPDFDocumentCreateWithProvider(dataProvider);
            CGDataProviderRelease(dataProvider);
        }
                
        trySaveInCache = YES;
    }
    
    // try to unlock it with a password
    if (documentRef && document.password && ![document.password isEqual:pdfPassword_]) {
        CGPDFDocumentUnlockWithPassword(documentRef, [document.password cStringUsingEncoding:NSASCIIStringEncoding]);
    }
    
    PSPDFDocumentProvider *documentProvider = nil;
    if (!documentRef) {
        // try to check if the pdf exists here, give additional error data
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        BOOL fileExists = [fileManager fileExistsAtPath:[pdfPath path]];
        if (fileExists) {
            PSPDFLogError(@"Cannot get document reference (although file exists) for %@", [pdfPath path]);
        }else {
            PSPDFLogError(@"Cannot get document reference, there is no file at %@!", [pdfPath path]);
        }
    }else {
        // try saving the document in the internal cache; if that one's not used at the moment
        if (trySaveInCache) {
            BOOL isLocked = [pdfGlobalLock_ tryLock];
            if (isLocked) {
                [self clearCacheNoLock:YES];
                pdfDocument_ = CGPDFDocumentRetain(documentRef);
                documentHash_ = [document hash];
                fileIndex_ = fileIndex;
                pdfPassword_ = document.password;
                [pdfGlobalLock_ unlock];
            }
        }
        
        documentProvider = [[PSPDFDocumentProvider alloc] initWithDocumentRef:documentRef URL:pdfPath];
        CGPDFDocumentRelease(documentRef);
    }
    OSSpinLockUnlock(&cacheAccessLock_);
    
    return documentProvider;
}

- (void)lockGlobal {
    PSPDFLogVerbose(@"Applying global lock");
    [pdfGlobalLock_ lock];
    PSPDFLogVerbose(@"Applying global lock... done");    
}

- (void)unlockGlobal {
    PSPDFLogVerbose(@"Freeing global lock");
    [pdfGlobalLock_ unlock];
    PSPDFLogVerbose(@"Freeing global lock... done");
}

- (void)freeWithPDFPageRef:(CGPDFPageRef)pdfPage {
    PSPDFLogVerbose(@"unlocking page");
    if (pdfPage != pdfPage_) {
        PSPDFLogError(@"Returned invalid pdfPage! Only global lock can create pdf references here!");
    }
    
    // page, doc is release here if we run low on mem
    [self clearCache:NO];
    [pdfGlobalLock_ unlock];
}

@end
