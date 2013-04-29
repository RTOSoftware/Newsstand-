//
//  PSPDFOutlineParser.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFOutlineParser.h"
#import "PSPDFOutlineElement.h"

@interface PSPDFOutlineParser() {
    NSMutableDictionary *outlinePageDict_;
}
@property(nonatomic, ps_weak) PSPDFDocument *document;
@property(nonatomic, strong) NSMutableDictionary *namedDestinations;
@end

@implementation PSPDFOutlineParser

@synthesize document = document_;
@synthesize outline = outline_;
@synthesize namedDestinations = namedDestinations_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// get string from CGPDFDictionary via key
NSString *stringFromCGPDFDictionary(CGPDFDictionaryRef dictRef, NSString *key);
NSString *stringFromCGPDFDictionary(CGPDFDictionaryRef dictRef, NSString *key) {
    NSString *string = nil;
    CGPDFStringRef objectString;
    if(CGPDFDictionaryGetString(dictRef, [key UTF8String], &objectString)) {
        string = (__bridge_transfer NSString *)CGPDFStringCopyTextString(objectString);
    }
    return string;
}

+ (CGPDFDictionaryRef)pageReferenceForObject:(CGPDFObjectRef)pageObjectRef {
    CGPDFDictionaryRef actualPageRef = nil;
    CGPDFObjectType pageObjectType = CGPDFObjectGetType(pageObjectRef);
    
    // first item in our array is the page dict
    if (pageObjectType == kCGPDFObjectTypeArray) {
        CGPDFArrayRef pageArrayRef;
        if(CGPDFObjectGetValue(pageObjectRef, pageObjectType, &pageArrayRef)) {
            CGPDFArrayGetDictionary(pageArrayRef, 0, &actualPageRef);
        }
    }else if(pageObjectType == kCGPDFObjectTypeDictionary) {
        CGPDFDictionaryRef pageDictRef;
        if (CGPDFObjectGetValue(pageObjectRef, pageObjectType, &pageDictRef)) {
            CGPDFArrayRef dRef;
            if(CGPDFDictionaryGetArray(pageDictRef, "D", &dRef)) {
                CGPDFArrayGetDictionary(dRef, 0, &actualPageRef);
            }
        }
    }else {
        PSPDFLogError(@"Warning: Parsing error - unexpected type before actualPageRef: %d", pageObjectType);
    }
    
    return actualPageRef;
}

// resolves a page dictionary reference to actual page index
+ (int)pageIndexForPageReference:(CGPDFDictionaryRef)pageReference documentRef:(CGPDFDocumentRef)documentRef cache:(NSMutableArray *)cache {
    int pageIndex = -1;
    
    NSUInteger pageCount = CGPDFDocumentGetNumberOfPages(documentRef);
    BOOL useCache = [cache count] == pageCount;
    for (int aPage=1; aPage <= pageCount; aPage++) {
        CGPDFDictionaryRef pageDict;
        if (useCache) {
            CGPDFPageRef page = (__bridge CGPDFPageRef)[cache objectAtIndex:aPage-1];
            pageDict = CGPDFPageGetDictionary(page);
        }else {
            CGPDFPageRef page = CGPDFDocumentGetPage(documentRef, aPage);
            [cache addObject:(__bridge id)page];
            pageDict = CGPDFPageGetDictionary(page);
        }
        
        if (pageIndex == -1 && pageDict == pageReference) {
            pageIndex = aPage;
            
            // don't stop on first use; fill cache!
            if (useCache || !cache) {
                break;
            }
        }
    }
    return pageIndex;
}

- (NSArray *)parseOutlineElements:(CGPDFDictionaryRef)outlineElementRef level:(NSUInteger)level error:(NSError **)error_  documentRef:(CGPDFDocumentRef)documentRef cache:(NSMutableArray *)cache {
    NSError *error;
    int pageIndex = -1;
    
    // parse title
    NSString *outlineTitle = stringFromCGPDFDictionary(outlineElementRef, @"Title");
    PSPDFLogVerbose(@"outline title: %@", outlineTitle);
    if (!outlineTitle) {
        if (error_) {
            *error_ = [NSError errorWithDomain:kPSPDFOutlineParserErrorDomain code:1 userInfo:nil];
        }
        return nil;
    }
    
    NSString *namedDestination = nil;
    CGPDFObjectRef destinationRef;
    if (CGPDFDictionaryGetObject(outlineElementRef, "Dest", &destinationRef)) {
        CGPDFObjectType destinationType = CGPDFObjectGetType(destinationRef);
        
        // named destination
        // http://stackoverflow.com/questions/4643489/how-do-i-retrieve-a-page-number-or-page-reference-for-an-outline-destination-in-a
        if (destinationType == kCGPDFObjectTypeString) {
            CGPDFStringRef destinationStrRef;
            if(CGPDFObjectGetValue(destinationRef, kCGPDFObjectTypeString, &destinationStrRef)) {
                namedDestination = (__bridge_transfer NSString *)CGPDFStringCopyTextString(destinationStrRef);
                //PSPDFLog(@"named destination [string]: %@", namedDestination);
            }
        }else if(destinationType == kCGPDFObjectTypeName) {
            const char *name = nil;
            if(CGPDFObjectGetValue(destinationRef, kCGPDFObjectTypeName, &name)) {
                namedDestination = [NSString stringWithCString:name encoding:NSUTF8StringEncoding];
                //PSPDFLog(@"named destination [name]: %@", namedDestination);
            }
        }else if(destinationType == kCGPDFObjectTypeArray) {
            // we expect an array at index 0
            CGPDFArrayRef destinationArray;
            if (CGPDFObjectGetValue(destinationRef, destinationType, &destinationArray)) {
                CGPDFDictionaryRef pageRef;
                if (CGPDFArrayGetDictionary(destinationArray, 0, &pageRef)) {
                    pageIndex = [[self class] pageIndexForPageReference:pageRef documentRef:documentRef cache:cache];
                }else {
                    PSPDFLogWarning(@"Expected Dictionary at index 0");
                }
            }else {
                PSPDFLogWarning(@"Failed fetching destination array (unexpected).");
            }
        }else {
            PSPDFLogWarning(@"Unsupported destination of type %d.", destinationType);
        }
    }else {
        // parse A dict
        CGPDFDictionaryRef aRef;
        if (CGPDFDictionaryGetDictionary(outlineElementRef, "A", &aRef)) {
            PSPDFLogVerbose(@"A dict: %ld", (long int)CGPDFDictionaryGetCount(aRef));
            
            // check that it's a GoTo
            const char *action = nil;
            if(CGPDFDictionaryGetName(aRef, "S", &action)) {
                if (strcmp(action, "GoTo") != 0) {
                    PSPDFLog(@"Invalid page reference, skipping entry.");
                }else {
                    namedDestination = stringFromCGPDFDictionary(aRef, @"D");
                    if(namedDestination) {
                        PSPDFLogVerbose(@"destination: %@", namedDestination);
                    }else {
                        // can also be an array with page content
                        CGPDFObjectRef pageRefContainer;
                        CGPDFDictionaryGetObject(outlineElementRef, "A", &pageRefContainer);
                        CGPDFDictionaryRef pageRef = [[self class] pageReferenceForObject:pageRefContainer];
                        if (pageRef) {
                            // write to header pageIndex
                            pageIndex = [[self class] pageIndexForPageReference:pageRef documentRef:documentRef cache:cache];
                        }
                    }
                }
            }
        }else {
            if (CGPDFDictionaryGetDictionary(outlineElementRef, "SE", &aRef)) {
                PSPDFLogVerbose(@"SE dict: %ld", (long int)CGPDFDictionaryGetCount(aRef));            
            }
        }
    }
    
    // parse next items
    NSArray *nextOutlineElements = nil;
    CGPDFDictionaryRef nextRef;
    if (CGPDFDictionaryGetDictionary(outlineElementRef, "Next", &nextRef)) {
        nextOutlineElements = [self parseOutlineElements:nextRef level:level error:&error documentRef:documentRef cache:cache]; // return all following outline references
    }
    
    // parse descendants
    NSArray *descendantOutlineElements = nil;
    CGPDFDictionaryRef descendantRef;
    if (CGPDFDictionaryGetDictionary(outlineElementRef, "First", &descendantRef)) {
        descendantOutlineElements = [self parseOutlineElements:descendantRef level:level+1 error:&error documentRef:documentRef cache:cache]; // return all following outline references
    }   
    
    PSPDFOutlineElement *outlineElement = [[PSPDFOutlineElement alloc] initWithTitle:outlineTitle page:(pageIndex >=0 ? pageIndex : 1) elements:descendantOutlineElements level:level];
    
    // needs to be resolved later
    if (namedDestination) {
        [namedDestinations_ setObject:outlineElement forKey:namedDestination];
    }
    
    NSMutableArray *outlineElements = [NSMutableArray arrayWithObject:outlineElement];
    if (nextOutlineElements) {
        [outlineElements addObjectsFromArray:nextOutlineElements];
    }
    
    return outlineElements;
}

// start parsing outline
- (NSArray *)parseOutline:(CGPDFDictionaryRef)outlineRef documentRef:(CGPDFDocumentRef)documentRef {
    NSError *error = nil;
    
    CGPDFInteger elements;
    if(CGPDFDictionaryGetInteger(outlineRef, "Count", &elements)) {
        PSPDFLog(@"parsing outline: %ld elements", (long int)elements);
    }else {
        PSPDFLogError(@"Error while parsing outline. No outlineRef?");
    }
    
    NSArray *outlineElements = nil;
    CGPDFDictionaryRef firstEntry;
    if (CGPDFDictionaryGetDictionary(outlineRef, "First", &firstEntry)) {
        NSMutableArray *pageCache = [NSMutableArray arrayWithCapacity:CGPDFDocumentGetNumberOfPages(documentRef)];
        outlineElements = [self parseOutlineElements:firstEntry level:0 error:&error documentRef:documentRef cache:pageCache];
    }else {
        PSPDFLogWarning(@"Error while parsing outline. First entry not found!");
    }
    
    return outlineElements;
}

// crawl through outline and build the dictionary
- (void)recursiveOutlineCrawler:(PSPDFOutlineElement *)outlineElement {
    NSNumber *pageNumber = [NSNumber numberWithInteger:outlineElement.page];
    if (![outlinePageDict_ objectForKey:pageNumber]) {
        [outlinePageDict_ setObject:outlineElement forKey:pageNumber];
    }
    
    for(PSPDFOutlineElement *childOutline in outlineElement.children) {
        [self recursiveOutlineCrawler:childOutline];
    }
}

- (void)buildPageNameCache:(NSArray *)outlineArray {
    outlinePageDict_ = [[NSMutableDictionary alloc] init];
    
    // crawl root outline, goes deep
    for(PSPDFOutlineElement *outlineElement in outlineArray) {
        [self recursiveOutlineCrawler:outlineElement];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithDocument:(PSPDFDocument *)document {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        document_ = document;        
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
     // weak
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (PSPDFOutlineElement *)outline {
    if (!outline_) {
        NSArray *outlineElements = [self parseDocument];
        outline_ = [[PSPDFOutlineElement alloc] initWithTitle:nil page:0 elements:outlineElements level:0];
    }
    return outline_;
}

- (PSPDFOutlineElement *)outlineElementForPage:(NSUInteger)page exactPageOnly:(BOOL)exactPageOnly {
    NSNumber *pageNumber = [NSNumber numberWithInteger:page];
    PSPDFOutlineElement *outline = [outlinePageDict_ objectForKey:pageNumber];
    
    // no outline, and not exact page needed? do a search
    if (!outline && !exactPageOnly) {
        NSArray *nextOutlines = [[outlinePageDict_ allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"page < %d", page]];
        [nextOutlines sortedArrayUsingDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"page" ascending:NO]]];
        outline = [nextOutlines lastObject];
    }
    
    return outline;
}

// parse dict, expect Kids or Names
+ (NSArray *)destinationNameArrayFromDestDictRef:(CGPDFDictionaryRef)destRef {
    NSMutableArray *destinationNameArrays = [NSMutableArray array];
    
    // Kids is a array full of dics that have the Names property
    CGPDFArrayRef kidsRef;
    if(CGPDFDictionaryGetArray(destRef, "Kids", &kidsRef)) {
        size_t arrayCount = CGPDFArrayGetCount(kidsRef);
        for(size_t i=0; i< arrayCount; i++) {
            CGPDFDictionaryRef arrayDictRef;
            if (CGPDFArrayGetDictionary(kidsRef, i, &arrayDictRef)) {
                NSArray *destinationNameArray = [self destinationNameArrayFromDestDictRef:arrayDictRef];
                [destinationNameArrays addObjectsFromArray:destinationNameArray];
            }
        }
    }else {
        // kids not available? we're at the end!
        CGPDFArrayRef destinationNameArray = nil;
        if(CGPDFDictionaryGetArray(destRef, "Names", &destinationNameArray)) {
            [destinationNameArrays addObject:[NSValue valueWithNonretainedObject:(__bridge id)destinationNameArray]];
        }else {
            PSPDFLogWarning(@"Names dict not found.");
        }
    }
    return destinationNameArrays;
}


// finds the string,array/doc, string, array/doc array (pagename -> pageref combo)
+ (NSArray *)destinationNameArrayFromCGPDFDictionaryRef:(CGPDFDictionaryRef)pdfDocDictionary {
    NSMutableArray *destinationNameArrays = [NSMutableArray array];
    CGPDFDictionaryRef nameRef, destRef;
    if (CGPDFDictionaryGetDictionary(pdfDocDictionary, "Names", &nameRef)) {
        if (CGPDFDictionaryGetDictionary(nameRef, "Dests", &destRef)) {
            NSArray *destinationNames = [self destinationNameArrayFromDestDictRef:destRef];
            [destinationNameArrays addObjectsFromArray:destinationNames];
        }
    }
    
    return destinationNameArrays;
}

+ (NSDictionary *)resolveDestNames:(NSSet *)destNames documentRef:(CGPDFDocumentRef)documentRef {
    NSMutableDictionary *resolvedDestNames = [NSMutableDictionary dictionary];
    
    // array is of structure name, array, name, array... (or dict in some cases)
    NSMutableArray *pageReferenceCache = [NSMutableArray arrayWithCapacity:CGPDFDocumentGetNumberOfPages(documentRef)];
    CGPDFDictionaryRef pdfDocDictionary = CGPDFDocumentGetCatalog(documentRef);
    NSArray *destinationNameArrays = [self destinationNameArrayFromCGPDFDictionaryRef:pdfDocDictionary];
    for (NSValue *destinationNameArrayValue in destinationNameArrays) {
        CGPDFArrayRef destinationNameArray = (__bridge CGPDFArrayRef)[destinationNameArrayValue nonretainedObjectValue];
        NSString *pageName = nil;
        CGPDFStringRef pageNameRef = nil;
        size_t innerArrayCount = CGPDFArrayGetCount(destinationNameArray);
        for(size_t i=0; i< innerArrayCount; i++) {
            if (i % 2 == 0) {
                CGPDFArrayGetString(destinationNameArray, i, &pageNameRef);
            }else {
                CGPDFDictionaryRef actualPageRef = nil;
                CGPDFObjectRef pageObjectRef; // can be array or dict!
                if(CGPDFArrayGetObject(destinationNameArray, i, &pageObjectRef)) {
                    actualPageRef = [self pageReferenceForObject:pageObjectRef];                    
                }
                
                if (actualPageRef && pageNameRef && [destNames count]) {
                    pageName = (__bridge_transfer NSString *)CGPDFStringCopyTextString(pageNameRef);
                    if([destNames containsObject:pageName]) {
                        // find page!
                        int pageIndex = [self pageIndexForPageReference:actualPageRef documentRef:documentRef cache:pageReferenceCache]; 
                        if (pageIndex >= 0) {
                            [resolvedDestNames setObject:[NSNumber numberWithInteger:pageIndex] forKey:pageName];
                        }
                    }
                }
            }
        }
    }
    return resolvedDestNames;
}

// parse document 
- (NSArray *)parseDocument {
    PSPDFDocumentProvider *documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self.document page:0];
    CGPDFDocumentRef documentRef = [documentProvider requestDocumentRef];
    CGPDFDictionaryRef pdfDocDictionary = CGPDFDocumentGetCatalog(documentRef);
    
    // get outline & loop through dictionary...
    NSArray *outlineArray = nil;
    CGPDFDictionaryRef outlineRef;
    if(CGPDFDictionaryGetDictionary(pdfDocDictionary, "Outlines", &outlineRef)) {
        self.namedDestinations = [NSMutableDictionary dictionary]; // prepare named destinations dict
        outlineArray = [self parseOutline:outlineRef documentRef:documentRef];
        
        // named destinations are pretty complex - need to search corresponding page for destination string
        if ([namedDestinations_ count] > 0) {
            __block BOOL resolvedAtLeastOnePage = NO;
            PSPDFLog(@"Named destinations found. Resolving...");
            
            NSDictionary *resolvedNames = [[self class] resolveDestNames:[NSSet setWithArray:[namedDestinations_ allKeys]] documentRef:documentRef];
            [resolvedNames enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                PSPDFOutlineElement *outlineElement = [namedDestinations_ objectForKey:key];
                if(outlineElement) {
                    NSInteger destPage = [obj integerValue];
                    PSPDFLogVerbose(@"MATCH FOUND: %@ (%@) is page %d", key, outlineElement.title, destPage);
                    outlineElement.page = destPage;
                    resolvedAtLeastOnePage = YES;
                }
            }];
            
            // sanity check. we don't want a *wrong* outline. worst case, remote it completely!
            if (!resolvedAtLeastOnePage) {
                PSPDFLogWarning(@"Outline pages couldn't be resolved, will remove outline now.");
                outlineArray = nil;
            }
            
            // restore memory
            self.namedDestinations = nil;
        }
    }else {
        PSPDFLogVerbose(@"No outline found.");
    }
    
    [self buildPageNameCache:outlineArray];
    
    if(!outlineArray) {
        outlineArray = [NSArray array]; // init empty array even if nothing found (to mark as parsed)
    }
    
    [documentProvider releaseDocumentRef:documentRef];
    return outlineArray;
}

@end
