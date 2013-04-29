//
//  PSPDFSearchOperation.m
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFSearchOperation.h"
#import "PSPDFDocumentSearcher.h"
#import "Scanner.h"
#import "PSPDFSimpleTextExtractor.h"

// tune the text preview algorithm
#define kSearchPreviewSubStringStart 20
#define kSearchPreviewSubStringEnd 70

@interface PSPDFSearchOperation() {
    NSMutableArray *searchResults_;
    NSMutableDictionary *pageTextDict_;
}
@property(nonatomic, copy) NSString *searchText;
@property(nonatomic, strong) NSArray *searchResults;
@property(nonatomic, assign) PSPDFDocument *document;
// internally only
@property(nonatomic, strong) Scanner *scanner;
@property(nonatomic, strong) NSURL *currentScannerFile;
@property(nonatomic, strong) NSMutableSet *selectionsUsed;
@property(nonatomic, strong) PSPDFDocumentProvider *documentProvider;
@end

@implementation PSPDFSearchOperation

@synthesize searchResults = searchResults_;
@synthesize document = document_;
@synthesize pageTextDict = pageTextDict_;
@synthesize searchText = searchText_;
@synthesize selectionSearchPages = selectionSearchPages_;
@synthesize delegate = delegate_;
@synthesize scanner = scanner_;
@synthesize currentScannerFile = currentScannerFile_;
@synthesize selectionsUsed = selectionsUsed_;
@synthesize searchMode = searchMode_;
@synthesize searchPages = searchPages_;
@synthesize documentProvider = documentProvider_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// get preview on a specific NSRange from pageText
- (NSString *)previewTextForRange:(NSRange)range pageText:(NSString *)pageText {
    if (range.location > kSearchPreviewSubStringStart) {
        range.location -= kSearchPreviewSubStringStart;
    }else {
        range.location = 0;
    }
    
    if (range.location + range.length + kSearchPreviewSubStringEnd < [pageText length]) {
        range.length += kSearchPreviewSubStringEnd;
    }else {
        range.length = [pageText length] - range.location; // right to the end
    }
    
    // prevent cutting in *between* words
    NSRange originalRange = range;
    while (range.length > 0 && range.location > 0 && range.location + range.length < [pageText length]) {
        BOOL isSpace = [pageText characterAtIndex:range.location-1] == ' ';
        if (isSpace) {
            break;
        }
        range.length--;
        range.location++;
    }
    
    // we failed (one really long word?) restore original range
    if (range.length == 0) {
        range = originalRange;
    }
    
    NSString *previewText = [pageText substringWithRange:range];
    return previewText;
}

// search a page for .searchText, with or without withSelection. Returns partial results.
- (NSArray *)searchPage:(NSUInteger)page withSelection:(BOOL)withSelection {
    PSPDFLogVerbose(@"Extracting text from %@, page %d withSelection:%d", document_.title, page, withSelection);
    NSMutableArray *results = [NSMutableArray array];
    
    @autoreleasepool {
        NSUInteger lastFoundLoc = 0;
        
        // get page content and save it into dict. first try document function
        NSString *pageText = [document_ pageContentForPage:page];
        
        // if selection is not required, try loading already parsed text from the dictionary
        if (!withSelection || [pageText length] == 0) {
            pageText = [pageTextDict_ objectForKey:[NSNumber numberWithInteger:page]];
        }
        
        // prepare CGPDFPageRef is no pageText is available
        CGPDFPageRef pageRef = nil;
        BOOL needLoadRef = !pageText || (withSelection && searchMode_ > PSPDFSearchLegacy);
        if (needLoadRef) {
            NSURL *urlForPage = [document_ pathForPage:page];
            if (!documentProvider_ || ![documentProvider_.URL isEqual:urlForPage]) {
                documentProvider_ = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:document_ page:page];
            }
            NSUInteger realPage = [document_ pageNumberForPage:page];  
            pageRef = [documentProvider_ requestPageRefForPage:realPage];
        }
        
        BOOL success = NO;
        if (needLoadRef) {            
            // support multiple document files
            BOOL scannerNeedsReinitialization = NO;
            if ([document_.files count] > 1) {
                NSURL *filePath = [document_ pathForPage:page];
                scannerNeedsReinitialization = ![currentScannerFile_ isEqual:filePath];
                self.currentScannerFile = filePath;
            }
            
            CGPDFDocumentRef documentRef = [documentProvider_ requestDocumentRef];
            if(!scanner_ || scannerNeedsReinitialization) {
                self.scanner = [[Scanner alloc] initWithDocument:documentRef];
                scanner_.keyword = searchText_;
            }
            scanner_.rawTextContent = [[NSMutableString alloc] init];
            
            // the scanner component is pretty tricky, a lot can go wrong here.
            // we really don't wanna crash, better catch the error and use legacy mode.
            @try {
                [scanner_ scanPage:pageRef];
                success = YES;
            }
            @catch (NSException *exception) {
                PSPDFLogError(@"PDF Text Scanner failed with exception: %@", exception);
            }
            [documentProvider_ releaseDocumentRef:documentRef];
            
            if (success) {
                pageText = scanner_.rawTextContent;
                [pageTextDict_ setObject:pageText forKey:[NSNumber numberWithInteger:page]];
                PSPDFLogVerbose(@"rawText: %@", pageText);
                
                for (Selection *selection in scanner_.selections) {
                    if (![selectionsUsed_ containsObject:selection]) {
                        // only use selection once
                        [selectionsUsed_ addObject:selection];
                        PSPDFSearchResult *searchResult = [[PSPDFSearchResult alloc] init];
                        searchResult.pageIndex = page;
                        searchResult.document = document_;
                        searchResult.selection = selection;
                        
                        // generate preview-text
                        // TODO: this should ideally be integrated in PDFKitten
                        NSRange range = [pageText rangeOfString:searchText_ options:NSCaseInsensitiveSearch range:NSMakeRange(lastFoundLoc, [pageText length] - lastFoundLoc)];
                        if (range.length > 0) {
                            searchResult.previewText = [self previewTextForRange:range pageText:pageText];
                            lastFoundLoc = range.location + range.length;
                        }
                        
                        searchResult.range = range;
                        [results addObject:searchResult];
                    }
                }
            }
        }
        
        // if we still have no pagetext, try the legacy algorithm to fetch!
        if (!pageText) {
            PSPDFSimpleTextExtractor *simpleTextExtractor = [[PSPDFSimpleTextExtractor alloc] init];
            pageText = [simpleTextExtractor pageContentWithPageRef:pageRef];
        }
        
        // quick search with already available pageText
        if (!success) {
            NSRange range;
            do {
                range = [pageText rangeOfString:searchText_ options:NSCaseInsensitiveSearch range:NSMakeRange(lastFoundLoc, [pageText length] - lastFoundLoc)];
                if (range.length > 0) {
                    PSPDFSearchResult *searchResult = [[PSPDFSearchResult alloc] init];
                    searchResult.pageIndex = page;
                    searchResult.document = document_;
                    searchResult.range = range;
                    searchResult.previewText = [self previewTextForRange:range pageText:pageText];
                    lastFoundLoc = range.location + range.length;
                    [results addObject:searchResult];
                }
            }while (range.length > 0);            
        }
        
        if (pageRef) {
            [documentProvider_ releasePageRef:pageRef];
            pageRef = nil;
            scanner_ = nil;
        }
    }
    [searchResults_ addObjectsFromArray:results];
    return results;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithDocument:(PSPDFDocument *)document searchText:(NSString *)searchText {
    if ((self = [super init])) {
        document_ = document; // weak
        searchText_ = [searchText copy];
        searchResults_ = [[NSMutableArray alloc] init];
        pageTextDict_ = [[NSMutableDictionary alloc] initWithCapacity:[document pageCount]];
        selectionsUsed_ = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)dealloc {
    document_ = nil;
    delegate_ = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

// thread entry point
- (void)main {    
    [delegate_ willStartSearchForString:self.searchText isFullSearch:searchPages_ == nil];
    
    // priorize selectionSearchPages
    [selectionSearchPages_ enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSUInteger page = [obj integerValue];
        if ([self isCancelled]) { return; } // stop search on cancel
        
        NSArray *results = [self searchPage:page withSelection:YES];
        [delegate_ didUpdateSearchForString:searchText_ newSearchResults:results forPage:page];        
    }];
    
    // make a limited search if this is set
    if (searchPages_) {
        [searchPages_ enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSUInteger page = [obj integerValue];
            NSArray *results = [self searchPage:page withSelection:NO];
            [delegate_ didUpdateSearchForString:searchText_ newSearchResults:results forPage:page];
        }];
    }else {
        // search all pages
        for (int page = 0; page < [document_ pageCount]; page++) {
            if ([self isCancelled]) { return; } // stop search on cancel
            NSNumber *pageNumber = [NSNumber numberWithInteger:page];
            if ([selectionSearchPages_ containsObject:pageNumber]) { continue; } // stop if already searched
            
            // if pageTextDict is empty, searchWithSelection is ignored
            BOOL searchWithSelection = selectionSearchPages_ == nil;
            NSArray *results = [self searchPage:page withSelection:searchWithSelection];
            [delegate_ didUpdateSearchForString:searchText_ newSearchResults:results forPage:page];
        }
    }
    
    // remove document provider cache
    documentProvider_ = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setPageTextDict:(NSDictionary *)pageTextDict {
    if (pageTextDict != pageTextDict_) {
        pageTextDict_ = [pageTextDict mutableCopy];
    }
}

#ifndef NS_BLOCK_ASSERTIONS
- (void)setSelectionSearchPages:(NSArray *)selectionSearchPages {
    if (selectionSearchPages_ != selectionSearchPages) {
        selectionSearchPages_ = selectionSearchPages;
        
        [selectionSearchPages_ enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSNumber *pageNr = (NSNumber *)obj;
            if ([pageNr integerValue] >= self.document.pageCount) {
                PSPDFLogError(@"Page Number out of range: %d (count: %d)", [pageNr integerValue], self.document.pageCount);
            }
        }];
    }
}
#endif

@end
