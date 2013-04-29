//
//  PSPDFDocument.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFGlobalLock.h"
#import <CommonCrypto/CommonDigest.h>

@interface PSPDFDocument() {
    NSMutableArray *files_; // needs to be mutable, so explicitely set.
    NSMutableDictionary *pageCountCache_; // needs to be mutable, so explicitely set.
    NSMutableDictionary *pageInfoCache_;
    NSMutableDictionary *fileUrlCache_;    
}
@property(nonatomic, strong, readonly) NSDictionary *pageCountCache;
@end

@implementation PSPDFDocument

@synthesize basePath = basePath_;
@synthesize files = files_;
@synthesize password = password_;
@synthesize data = data_;
@synthesize uid = uid_;
@synthesize title = title_;
@synthesize searchEnabled = searchEnabled_;
@synthesize aspectRatioEqual = aspectRatioEqual_;
@synthesize pageCountCache = pageCountCache_;
@synthesize documentSearcher = documentSearcher_;
@synthesize outlineParser = outlineParser_;
@synthesize annotationParser = annotationParser_;
@synthesize outlineEnabled = outlineEnabled_;
@synthesize annotationsEnabled = annotationsEnabled_;
@synthesize twoStepRenderingEnabled = twoStepRenderingEnabled_;
@synthesize displayingPdfController = displayingPdfController_;
@dynamic fileUrl;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// returns a file url with added basePath, if there is one set
- (NSURL *)fileUrlWithFileName:(NSString *)fileName {
    NSURL *path = [fileUrlCache_ objectForKey:fileName];
    
    if (!path) {
        if (self.basePath) {
            path = [self.basePath URLByAppendingPathComponent:fileName];
        }else {
            path = [NSURL fileURLWithPath:fileName];
        }
        [fileUrlCache_ setObject:path forKey:fileName];
    }
    
    return path;
}

// returns pdf metadata. not exposed.
// see http://pdf.editme.com/pdfua-docinfodictionary for a list of available properties.
- (NSDictionary *)metadata {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithCapacity:1];
    CGPDFDictionaryRef metadataDict = nil;
    
    // open pdf non-blocking and look into the meta-data
    PSPDFDocumentProvider *documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self page:0];
    if(documentProvider) {
        CGPDFDocumentRef documentRef = [documentProvider requestDocumentRef];
        metadataDict = CGPDFDocumentGetInfo(documentRef);
        
        CGPDFStringRef titleRef;
        if(CGPDFDictionaryGetString(metadataDict, "Title", &titleRef)) {
            NSString *title = (__bridge_transfer NSString *)CGPDFStringCopyTextString(titleRef); // toll-free bridging ftw!
            PSPDFLogVerbose(@"Title found: %@", title);                
            [metadata setObject:title forKey:@"Title"];
        }
        
        [documentProvider releaseDocumentRef:documentRef];
    }
    
    return metadata;
}

- (PSPDFPageInfo *)pageInfoForPageInternal_:(NSUInteger)page {
    PSPDFPageInfo *pageInfo = (__bridge PSPDFPageInfo *)CFDictionaryGetValue((__bridge CFDictionaryRef)pageInfoCache_, (void *)page);
    return pageInfo;
}

// helper that generates a unique id depending on the document files
- (NSString *)generateUID {
    NSMutableString *stringHash = [NSMutableString stringWithString:title_ ? title_ : @""];
    if ([files_ count]) {
        if (basePath_) {
            [stringHash appendString:[basePath_ absoluteString]];
        }
        for (NSString *file in files_) {
            [stringHash appendString:file];
        }
    }
    
    NSData *md5HashData = data_;
    if (!data_ && [stringHash length]) {
        md5HashData = [stringHash dataUsingEncoding:NSUTF8StringEncoding];
    }

    // generate MD5 hash
    if (md5HashData) {
        unsigned char md[CC_MD5_DIGEST_LENGTH];
        CC_MD5([md5HashData bytes], [md5HashData length], md);
        NSMutableString *digest = [NSMutableString string];
        for (NSUInteger i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
            [digest appendFormat:@"%02x", md[i]];
        }
        return digest;
    }

    return nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

+ (PSPDFDocument *)PDFDocument {
    PSPDFDocument *pdfDocument = [[[self class] alloc] init];
    return pdfDocument;
}

+ (PSPDFDocument *)PDFDocumentWithData:(NSData *)data {
    PSPDFDocument *pdfDocument = [(PSPDFDocument *)[[self class] alloc] initWithData:data];
    return pdfDocument;
}

+ (PSPDFDocument *)PDFDocumentWithUrl:(NSURL *)url {
    PSPDFDocument *pdfDocument = [(PSPDFDocument *)[[self class] alloc] initWithUrl:url];
    return pdfDocument;
}

+ (PSPDFDocument *)PDFDocumentWithBaseUrl:(NSURL *)baseUrl files:(NSArray *)files {
    PSPDFDocument *pdfDocument = [[[self class] alloc] initWithBaseUrl:baseUrl files:files];
    return pdfDocument;
}

- (id)initWithBaseUrl:(NSURL *)basePath files:(NSArray *)files {
    if ((self = [self init])) {
        basePath_ = [basePath copy];
        [files_ addObjectsFromArray:files];
        uid_ = [self generateUID];
    }
    return self;
}

- (id)initWithUrl:(NSURL *)url {
    if ((self = [self init])) {
        [self setFileUrl:url];
    }
    return self;
}

- (id)initWithData:(NSData *)data {
    if ((self = [self init])) {
        data_ = data;
        uid_ = [self generateUID];
    }
    return self;
}

- (id)init {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        files_ = [[NSMutableArray alloc] init];
        
        // pageInfoCache uses a special dict that doesn't need boxing
        pageInfoCache_ = (__bridge_transfer NSMutableDictionary *)CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
        pageCountCache_ = [[NSMutableDictionary alloc] init];
        fileUrlCache_ = [[NSMutableDictionary alloc] init];
        pageCount_ = NSUIntegerMax;
        twoStepRenderingEnabled_ = NO;
        aspectRatioEqual_ = NO;
        searchEnabled_ = YES;
        outlineEnabled_ = YES;
        annotationsEnabled_ = YES;
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    documentSearcher_.delegate = nil;
    displayingPdfController_ = nil;
}

- (NSUInteger)hash {
    return [self.uid hash];
}

- (BOOL)isEqual:(id)other {
    if ([other isKindOfClass:[self class]]) {
        if (![self.uid isEqual:[other uid]] || !self.uid || ![other uid]) {
            return NO;
        }
        return YES; 
    }
    else return NO;  
}

- (NSString *)description {
    NSString *description = [NSString stringWithFormat:@"<PSPDFDocument uid:%@ files:%d pageCount:%d>", self.uid, [self.files count], [self pageCount]];
    return description;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setFileUrl:(NSURL *)fileUrl {
    if (fileUrl) {
        basePath_ = [[fileUrl URLByDeletingLastPathComponent] copy];
        [files_ removeAllObjects];
        NSString  *lastPathComponent = [fileUrl lastPathComponent];
        if (lastPathComponent) {
            [files_ addObject:lastPathComponent];
        }else {
            PSPDFLogWarning(@"No files set? (fileUrl: %@)", fileUrl);
        }
        uid_ = [self generateUID];
    }
}

- (NSURL *)fileUrl {
    // return early if no file is set
    if (![self.files count]) {
        return nil;
    }
    
    return [self.basePath URLByAppendingPathComponent:[self.files objectAtIndex:0]];
}

- (NSArray *)filesWithBasePath {
    NSMutableArray *newFiles = [NSMutableArray arrayWithCapacity:[files_ count]];
    for (NSString *fileName in files_) {
        [newFiles addObject:[self fileUrlWithFileName:fileName]];
    }
    return newFiles;
}

/// appends a file to the current document. No PDF gets modified, just displayed together.
- (void)appendFile:(NSString *)file {
    if (!file) {
        PSPDFLogWarning(@"appendFile called with nil argument!");
        return;
    }
    [files_ addObject:file];
    [self clearCacheForced:YES];
}

- (PSPDFPageInfo *)pageInfoForPage:(NSUInteger)page pageRef:(CGPDFPageRef)pageRef {
    if (page >= [self pageCount]) {
        if ([self pageCount] > 0) { // don't warn if pdf is invalid
            PSPDFLogWarning(@"Invalid page %d, returning nil.", page);
        }
        return nil;
    }
    
    // if aspect ratio is the same on every page, only parse page once.
    if (self.isAspectRatioEqual) {
        page = 0;
    }
    
    PSPDFPageInfo *pageInfo = [self pageInfoForPageInternal_:page];
    if (!pageInfo) {
        
        // this may block our UI thread - so we really should pre-calculate this.
        @autoreleasepool {
            PSPDFDocumentProvider *documentProvider = nil;
            if (!pageRef) {
                documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self page:page];
                pageRef = [documentProvider requestPageRefForPage:[self pageNumberForPage:page]];
            }
            if (!pageRef) {
                PSPDFLog(@"Warning: Failed opening pdf page: %@", pageRef);
            }else {
                // fetch page properties for caching
                int pageRotation = CGPDFPageGetRotationAngle(pageRef);
                CGRect pageRect = CGPDFPageGetBoxRect(pageRef, kCGPDFCropBox);
                
                // cache rect and rotation for faster lookup
                pageInfo = [PSPDFPageInfo pageInfoWithRect:pageRect rotation:pageRotation];
                pageInfo.page = page;
                pageInfo.document = self;
                CFDictionarySetValue((__bridge CFMutableDictionaryRef)pageInfoCache_, (void *)page, (__bridge const void *)pageInfo);
                [documentProvider releasePageRef:pageRef];
            }
        }
    }
    
    return pageInfo;
}

- (BOOL)hasPageInfoForPage:(NSUInteger)page {
    PSPDFPageInfo *pageInfo = [self pageInfoForPageInternal_:page];
    return pageInfo != nil;
}

- (PSPDFPageInfo *)pageInfoForPage:(NSUInteger)page {
    return [self pageInfoForPage:page pageRef:nil];
}

- (PSPDFPageInfo *)nearestPageInfoForPage:(NSUInteger)page {
    PSPDFPageInfo *pageInfo = nil;
    page++;
    do {
        pageInfo = [self pageInfoForPageInternal_:page-1];
        page--;
    }while (!pageInfo && page > 0);
    return pageInfo;
}


// helper for pageInfoForPage, returns rotatedPageRect
- (CGRect)rectBoxForPage:(NSUInteger)page {
    PSPDFPageInfo *pageInfo = [self pageInfoForPage:page];
    if (pageInfo) {
        return pageInfo.rotatedPageRect;
    }else {
        if ([self pageCount]) {
            PSPDFLogWarning(@"Returning empty rect.");
        }
        return CGRectZero;
    }
}

// helper for pageInfoForPage, returns pageRotation
- (int)rotationForPage:(NSUInteger)page {
    PSPDFPageInfo *pageInfo = [self pageInfoForPage:page];
    if (pageInfo) {
        return pageInfo.pageRotation;
    }else {
        PSPDFLogWarning(@"Returning 0 rotation.");
        return 0;
    }
}

- (BOOL)pageCountNeedsCalculation {
    BOOL pageCountNeedsCalculation = pageCount_ == NSUIntegerMax;
    return pageCountNeedsCalculation;
}

// analyze package and count files
- (NSUInteger)pageCount {
    // lazy, one time calculation
    if ([self pageCountNeedsCalculation]) {
        @synchronized(self) {
            pageCount_ = 0;
            NSInteger pos = 0;
            NSLog(@"%@",self.files);
            for (NSString *file in self.files) {
                NSLog(@"%@",file);
                NSURL *pdfUrl = [self fileUrlWithFileName:file]; 
                CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)pdfUrl);
                if (!document) {
                    PSPDFLog(@"Warning: failed to open document: %@", pdfUrl);
                }else {
                    NSUInteger pages = CGPDFDocumentGetNumberOfPages(document);
                    pageCount_ += pages;
                    [pageCountCache_ setObject:[NSNumber numberWithInt:pages] forKey:[NSNumber numberWithInteger:pos]];
                    CGPDFDocumentRelease(document);
                }
                pos++;
            }
            if (pageCount_ == 0 && self.data) {
                CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)self.data);
                CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(dataProvider);
                pageCount_ = CGPDFDocumentGetNumberOfPages(document);
                CGPDFDocumentRelease(document);
                CGDataProviderRelease(dataProvider);
            }
        };
    }
    
    return pageCount_;
}

- (NSDictionary *)pageCountCache {
    [self pageCount]; // ensure page is counted.
    return pageCountCache_;
}

// if we have multiple files, there is a page offset from logical to file-based page count
- (NSUInteger)pageOffsetForPage:(NSUInteger)page {
    NSInteger fileIndex = [self fileIndexForPage:page];
    NSInteger pos = 0;
    NSUInteger offset = 0;
    for (NSString *aFile in self.files) {
        if (pos == fileIndex) {
            break;
        }
        NSUInteger aFilePageCount = [[self.pageCountCache objectForKey:[NSNumber numberWithInteger:pos]] integerValue];
        offset += aFilePageCount;
        pos++;
    }
    return offset;    
}

- (NSInteger)fileIndexForPage:(NSUInteger)page {
    NSInteger pageIndex = page;
    NSInteger fileIndex = -1;
    
    // optimized, so that pageCountCache doesn't need to be created in the simplest case
    if ([self.files count] == 1) {
        fileIndex = 0;
    }else {
        NSInteger pos = 0;
        for (NSString *file in self.files) {
            NSUInteger aFilePageCount = [[self.pageCountCache objectForKey:[NSNumber numberWithInteger:pos]] integerValue]; 
            pageIndex -= aFilePageCount;
            if (pageIndex < 0) {
                fileIndex = pos;
                break;
            }
            pos++;
        }
    }
    return fileIndex;
}

- (NSURL *)URLForFileIndex:(NSInteger)fileIndex {
    NSString *fileForPage = nil;
    if (fileIndex >= 0 && fileIndex < [self.files count]) {
        fileForPage = [self.files objectAtIndex:fileIndex];
    }
    if (!fileForPage) {
        if (!self.data) {
            PSPDFLogWarning(@"Path for fileIndex %d is missing!", fileIndex);
        }
        return nil;
    }
    NSURL *path = [self fileUrlWithFileName:fileForPage];
    return path;    
}

- (NSURL *)pathForPage:(NSUInteger)page {
    NSInteger fileIndex = [self fileIndexForPage:page];
    NSURL *URL = [self URLForFileIndex:fileIndex];
    return URL;
}

- (NSUInteger)pageNumberForPage:(NSUInteger)page {
    NSUInteger pageOffset = [self pageOffsetForPage:page];
    NSUInteger pageNumberForPage = page - pageOffset + 1; // pdf starts at 1
    return pageNumberForPage;
}

- (void)clearCache {
    [self clearCacheForced:NO];
}


- (void)clearCacheForced:(BOOL)forced {
    if (!self.displayingPdfController || forced) {
        PSPDFLogVerbose(@"clearing cache for %@", self);
        
        // remove cached parsers
        documentSearcher_.delegate = nil;
        documentSearcher_ = nil;
        outlineParser_ = nil;
        annotationParser_ = nil;
    }
    
    // minimal memory usage - not worth a delete unless forced is used
    if (forced) {
        [pageCountCache_ removeAllObjects];
        [pageInfoCache_ removeAllObjects];
        [fileUrlCache_ removeAllObjects];
        pageCount_ = NSUIntegerMax;
    }
}

// fills up rect cache
- (void)fillCache {
    // only needed if aspect ratio is *not* equal, else just break
    if (self.aspectRatioEqual) {
        return;
    }
    
    // ensure we're not called more than once at the same time
    @synchronized(uid_) {
        NSURL *lastUrl = nil;
        NSUInteger pageCount = [self pageCount];
        CGPDFDocumentRef documentRef = nil;
        
        // fill up pageInfo cache, optimized!
        for (int i=0; i < pageCount; i++) {
            NSURL *path = [self pathForPage:i];
            if (!path) {
                break;
            }
            // only re-open the document if we're combined
            if (![path isEqual:lastUrl]) {
                CGPDFDocumentRelease(documentRef);
                documentRef = CGPDFDocumentCreateWithURL((__bridge CFURLRef)path);
                lastUrl = path;
                if (documentRef && self.password) {
                    CGPDFDocumentUnlockWithPassword(documentRef, [self.password cStringUsingEncoding:NSASCIIStringEncoding]);
                }
            }
            
            @autoreleasepool {
                CGPDFPageRef pageRef = CGPDFDocumentGetPage(documentRef, [self pageNumberForPage:i]);
                PSPDFPageInfo *pageInfo = [self pageInfoForPage:i pageRef:pageRef];
#pragma unused(pageInfo)
                PSPDFLogVerbose(@"cached pageInfo: %@ for page %d", pageInfo, i);
            }
        }
        CGPDFDocumentRelease(documentRef);
    }
}

- (void)setBasePath:(NSURL *)aBasePath {
    if (basePath_ != aBasePath) {
        basePath_ = aBasePath;
        [self clearCacheForced:YES];
    }
}

- (void)setFiles:(NSArray *)aFiles {
    if (files_ != aFiles) {
        files_ = [aFiles mutableCopy];
        [self clearCacheForced:YES];
        
        // if uid is not set at this point, generate one!
        if (!uid_) {
            uid_ = [self generateUID];
        }    
    }
}

- (void)setTitle:(NSString *)title {
    if (title_ != title) {
        title_ = title;
        
        // if uid is not set at this point, use title as uid!
        if (!uid_) {
            uid_ = [self generateUID];
        }
    }
}

- (NSString *)title {
    // if title is not set, try to load it from the pdf
    if (!title_) {
        @synchronized(self) { // lock and make a threadsafe query of the title
            if (!title_) {
                @autoreleasepool {
                    NSDictionary *metadata = [self metadata];
                    if (metadata) {
                        PSPDFLog(@"Title for %@ is not set. Looking in the pdf metadata...", uid_);
                        NSString *title = [metadata objectForKey:@"Title"];
                        
                        // fallback to filename if title was not found
                        title_ = ([title length] > 0) ? title : [[[self pathForPage:0] lastPathComponent] copy];
                    }
                }
            }
        }
    }
    
    return title_;
}

- (BOOL)allowsPrinting {
    BOOL allowsPrintingResult = NO;
    
    PSPDFDocumentProvider *documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self page:0];
    CGPDFDocumentRef documentRef = [documentProvider requestDocumentRef];
    allowsPrintingResult = CGPDFDocumentAllowsPrinting(documentRef);
    
    [documentProvider releaseDocumentRef:documentRef];
    
    return allowsPrintingResult;
}

- (BOOL)isEncrypted {
    BOOL encryptedResult = NO;
    
    PSPDFDocumentProvider *documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self page:0];
    CGPDFDocumentRef documentRef = [documentProvider requestDocumentRef];
    encryptedResult = CGPDFDocumentIsEncrypted(documentRef);
    
    [documentProvider releaseDocumentRef:documentRef];
    
    return encryptedResult;
}

// Has the PDF file been unlocked (password supplied, which can be empty).
- (BOOL)isLocked {
    BOOL lockedResult = NO;
    
    PSPDFDocumentProvider *documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self page:0];
    CGPDFDocumentRef documentRef = [documentProvider requestDocumentRef];
    lockedResult = !CGPDFDocumentIsUnlocked(documentRef);
    
    [documentProvider releaseDocumentRef: documentRef];
    
    return lockedResult;
}

- (BOOL)unlockWithPassword:(NSString *)password {
    BOOL result = YES;
    
    if (password && self.isEncrypted && self.isLocked) {
        NSURL* urlForPage = [self pathForPage:0];
        if (urlForPage == nil) {
            PSPDFDocumentProvider* documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self page:0]; 
            CGPDFDocumentRef documentRef = [documentProvider requestDocumentRef];
            
            // PDF stuff works with c-strings. Convert before sending to CGPDF layer.
            const char *convertedPassword = [password cStringUsingEncoding: NSASCIIStringEncoding];
            if(convertedPassword) {
                result = CGPDFDocumentUnlockWithPassword(documentRef, convertedPassword) ? YES : NO;
            }
            
            [documentProvider releaseDocumentRef:documentRef];
        }
    }
    
    return result;
}

- (BOOL)isValid {
    BOOL isValid = [self pageCount] > 0;
    return isValid;
}

// override if needed
- (NSURL *)thumbnailPathForPage:(NSUInteger)page { 
    return nil;
}

// override if needed
- (BOOL)shouldDrawOverlayRectForSize:(PSPDFSize)size {
    return NO;
}

// override if needed
- (void)drawOverlayRect:(CGRect)rect inContext:(CGContextRef)context forPage:(NSUInteger)page zoomScale:(CGFloat)zoomScale size:(PSPDFSize)size {
}

// override if needed
- (UIColor *)backgroundColorForPage:(NSUInteger)page {
    return [UIColor whiteColor];
}

// override if needed
- (NSString *)pageContentForPage:(NSUInteger)page {
    return nil;
}

- (PSPDFDocumentSearcher *)documentSearcher {
    // lazy-init
    if (!documentSearcher_) {
        documentSearcher_ = [[PSPDFDocumentSearcher alloc] initWithDocument:self];
    }
    return documentSearcher_;
}

- (PSPDFOutlineParser *)outlineParser {
    // lazy-init
    if (!outlineParser_ && self.isOutlineEnabled) {
        outlineParser_ = [[PSPDFOutlineParser alloc] initWithDocument:self];
    }
    return self.isOutlineEnabled ? outlineParser_ : nil;
}

// override if needed
- (PSPDFAnnotationParser *)annotationParser {
    // lazy-init
    if (!annotationParser_ && self.isAnnotationsEnabled) {
        annotationParser_ = [[PSPDFAnnotationParser alloc] initWithDocument:self];
    }
    
    // only return if annotation is enabled
    return self.isAnnotationsEnabled ? annotationParser_ : nil;
}

@end
