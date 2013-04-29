//
//  PSPDFSimpleTextExtractor.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFSimpleTextExtractor.h"
#import "PSPDFKit.h"

@interface PSPDFSimpleTextExtractor() {
    CGPDFOperatorTableRef table_;
}
@property (nonatomic, strong) NSMutableString *currentData;
@end

@implementation PSPDFSimpleTextExtractor

@synthesize currentData = currentData_;

void arrayCallback(CGPDFScannerRef inScanner, void *userInfo);
void stringCallback(CGPDFScannerRef inScanner, void *userInfo);

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - pdf parsing

// http://stackoverflow.com/questions/4737305/how-to-search-text-in-pdf-document-with-quartz
void arrayCallback(CGPDFScannerRef inScanner, void *userInfo) {
    PSPDFSimpleTextExtractor *searcher = (__bridge PSPDFSimpleTextExtractor *)userInfo;
    CGPDFArrayRef array;
    bool success = CGPDFScannerPopArray(inScanner, &array);
    
    for(size_t n = 0; n < CGPDFArrayGetCount(array); n += 2) {
        if(n >= CGPDFArrayGetCount(array)) {
            continue;
        }
        
        CGPDFStringRef string;
        success = CGPDFArrayGetString(array, n, &string);
        if(success) {
            NSString *data = (__bridge_transfer NSString *)CGPDFStringCopyTextString(string);
            [searcher.currentData appendFormat:@"%@", data];
        }
    }
}

void stringCallback(CGPDFScannerRef inScanner, void *userInfo) {
    PSPDFSimpleTextExtractor *searcher = (__bridge PSPDFSimpleTextExtractor *)userInfo;
    CGPDFStringRef string;
    
    bool success = CGPDFScannerPopString(inScanner, &string);
    
    if(success) {
        NSString *data = (__bridge_transfer NSString *)CGPDFStringCopyTextString(string);
        [searcher.currentData appendFormat:@"%@", data];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        table_ = CGPDFOperatorTableCreate();
        CGPDFOperatorTableSetCallback(table_, "TJ", arrayCallback);
        CGPDFOperatorTableSetCallback(table_, "Tj", stringCallback);
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    CGPDFOperatorTableRelease(table_);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

// returns text as NSString or nil on failure
- (NSString *)pageContentWithPageRef:(CGPDFPageRef)pageRef {
    [self setCurrentData:[NSMutableString string]];
    CGPDFContentStreamRef contentStream = CGPDFContentStreamCreateWithPage(pageRef);
    CGPDFScannerRef scanner = CGPDFScannerCreate(contentStream, table_, (__bridge void *)(self));
    bool success = CGPDFScannerScan(scanner);
    if (!success) {
        PSPDFLogWarning(@"Failed extracting text from %@", pageRef);
    }
    CGPDFScannerRelease(scanner);
    CGPDFContentStreamRelease(contentStream);
    
    // return plain NSString
    return success ? [self.currentData copy] : nil;
}

@end
