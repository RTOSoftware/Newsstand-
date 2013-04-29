//
//  PSPDFAnnotationParser.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFAnnotationParser.h"
#import "PSPDFKit.h"
#import "PSPDFAnnotation.h"
#import "PSPDFVideoAnnotationView.h"
#import "PSPDFWebAnnotationView.h"
#import "PSPDFLinkAnnotationView.h"
#import "PSPDFHighlightAnnotationView.h"
#import "PSPDFDocumentProvider.h"
#import "PSPDFYouTubeAnnotationView.h"
#import "PSPDFImageAnnotation.h"

@interface PSPDFAnnotationParser () {
    NSMutableDictionary *pageCache_;
    dispatch_queue_t dictCacheQueue_;
}
- (void)parsePageAnnotation:(PSPDFAnnotation *)annotation dictionary:(CGPDFDictionaryRef)annotationDictionary document:(CGPDFDocumentRef)documentRef;
- (void)parseHighlightAnnotation:(PSPDFAnnotation *)annotation dictionary:(CGPDFDictionaryRef)annotationDictionary document:(CGPDFDocumentRef)documentRef;
- (CGPDFArrayRef)findDestinationByName:(const char *)destinationName inDestsTree:(CGPDFDictionaryRef)node;
- (NSUInteger)replaceFirstOccurenceOfString:(NSString *)string withString:(NSString *)newString mutableString:(NSMutableString *)mutableString;
- (PSPDFAnnotationType)annotationTypeForDictionary:(CGPDFDictionaryRef)annotationDictionary document:(CGPDFDocumentRef)documentRef;
@property(nonatomic, strong) NSMutableDictionary *namedDestinations;
@end

@implementation PSPDFAnnotationParser

@synthesize document = document_;
@synthesize protocolString = protocolString_;
@synthesize namedDestinations = namedDestinations_;
@synthesize createTextHighlightAnnotations = createTextHighlightAnnotations_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithDocument:(PSPDFDocument *)document {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        dictCacheQueue_ = dispatch_queue_create("com.petetersteinberger.pspdfkit.annotationCache", NULL);
        document_ = document;
        protocolString_ = @"nafa://";
        pageCache_ = [[NSMutableDictionary alloc] init];         // annotation page cache
        namedDestinations_ = [[NSMutableDictionary alloc] init]; // resolve page refs
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
   // dispatch_release(dictCacheQueue_);
    document_ = nil; // weak
    pageCache_ = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setAnnotations:(NSArray *)annotations forPage:(NSUInteger)page {
    dispatch_sync(dictCacheQueue_, ^{
        if (annotations) {
            [pageCache_ setObject:annotations forKey:[NSNumber numberWithInteger:page]];
        }else {
            [pageCache_ removeObjectForKey:[NSNumber numberWithInteger:page]];
        }
    });
}

- (void)setProtocolString:(NSString *)protocolString {
    if (protocolString != protocolString_) {
        protocolString_ = protocolString;
        [pageCache_ removeAllObjects]; // clear page cache after protocol has been re-set
    }
}

- (UIView <PSPDFAnnotationView>*)createAnnotationViewForAnnotation:(PSPDFAnnotation *)annotation frame:(CGRect)annotationRect {
    UIView <PSPDFAnnotationView> *annotationView = nil;
    
    // annotation factory
    if(annotation) {
        switch (annotation.type) {
            case PSPDFAnnotationTypeVideo:
            case PSPDFAnnotationTypeAudio: {
                PSPDFVideoAnnotationView *videoAnnotation = [[PSPDFVideoAnnotationView alloc] initWithFrame:annotationRect];
                videoAnnotation.URL = annotation.URL;
                
                if ([annotation.options objectForKey:@"autostart"]) {
                    videoAnnotation.autostartEnabled = [[annotation.options objectForKey:@"autostart"] boolValue];
                }
                
                videoAnnotation.annotation = annotation;
                annotationView = videoAnnotation;
            }break;
            case PSPDFAnnotationTypeYouTube: {
                PSPDFYouTubeAnnotationView *youTubeView = [[PSPDFYouTubeAnnotationView alloc] initWithYouTubeURL:annotation.URL frame:annotationRect annotation:annotation showNativeFirst:YES];
                annotationView = youTubeView;
            }break;
            case PSPDFAnnotationTypeImage: {
                PSPDFImageAnnotation *imageAnnotation = [[PSPDFImageAnnotation alloc] initWithFrame:annotationRect];
                imageAnnotation.URL = annotation.URL;
                imageAnnotation.annotation = annotation;
                annotationView = imageAnnotation;
            }break;
            case PSPDFAnnotationTypeBrowser: {
                PSPDFWebAnnotationView *webView = [[PSPDFWebAnnotationView alloc] initWithFrame:annotationRect];
                [webView.webView loadRequest:[NSURLRequest requestWithURL:annotation.URL]];
                annotationView = webView;
            }break;
            case PSPDFAnnotationTypeLink: {
                PSPDFLinkAnnotationView *linkAnnotationView = [[PSPDFLinkAnnotationView alloc] initWithFrame:annotationRect];
                linkAnnotationView.annotation = annotation;
                annotationView = linkAnnotationView;
            }break;
            case PSPDFAnnotationTypeHighlight : {
                if (createTextHighlightAnnotations_) {
                    PSPDFHighlightAnnotationView *highlightAnnotation = [[PSPDFHighlightAnnotationView alloc] initWithFrame:annotationRect];
                    highlightAnnotation.annotation = annotation;
                    annotationView = highlightAnnotation;
                }
            }break;
            default: {
                PSPDFLogVerbose(@"Annotation %@ not handled.", annotation);
            }
        }
    }
    return annotationView;
}

- (BOOL)hasLoadedAnnotationsForPage:(NSUInteger)page {
    NSNumber *pageNumber = [NSNumber numberWithInteger:page];
    __block NSArray *annotations;
    dispatch_sync(dictCacheQueue_, ^{
        annotations = [pageCache_ objectForKey:pageNumber];
    });
    
    BOOL hasLoaded = annotations != nil;
    return hasLoaded;
}

- (NSArray *)annotationsForPage:(NSUInteger)page filter:(PSPDFAnnotationFilter)filter {
    return [self annotationsForPage:page filter:filter pageRef:nil];
}

- (NSArray *)annotationsForPage:(NSUInteger)page filter:(PSPDFAnnotationFilter)filter pageRef:(CGPDFPageRef)pageRef {
    __block NSArray *annotations = nil;
    
    PSPDFDocument *document = self.document;
    
    // sanity check
    if (!document) {
        PSPDFLogWarning(@"No document attached, returning nil.");
        return nil;
    }
    
    NSNumber *pageNumber = [NSNumber numberWithInteger:page];
    dispatch_sync(dictCacheQueue_, ^{
        annotations = [pageCache_ objectForKey:pageNumber];
    });
    
    if (!annotations) {
        @synchronized(self) {
            PSPDFLogVerbose(@"fetching annotations for page %d", page);
            NSMutableArray *newAnnotations = [NSMutableArray array];
            
            // if no pageRef was given, open document ourself
            PSPDFDocumentProvider *documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self.document page:page];
            if (!pageRef) {
                documentProvider = [[PSPDFGlobalLock sharedPSPDFGlobalLock] documentProviderForDocument:self.document page:page];
                pageRef = [documentProvider requestPageRefForPage:[self.document pageNumberForPage:page]];
            }
            CGPDFDocumentRef documentRef = CGPDFPageGetDocument(pageRef);
            CGPDFDictionaryRef pageDictionary = CGPDFPageGetDictionary(pageRef);
            CGPDFArrayRef annotsArray = NULL;
            
            // PDF links are link annotations stored in the page's Annots array.
            CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotsArray);
            if (annotsArray != NULL) {
                int annotsCount = CGPDFArrayGetCount(annotsArray);
                
                for (int j = 0; j < annotsCount; j++) {
                    CGPDFDictionaryRef annotationDictionary = NULL;            
                    if (CGPDFArrayGetDictionary(annotsArray, j, &annotationDictionary)) {
                        
                        // identify the current anntotation
                        PSPDFAnnotationType type = [self annotationTypeForDictionary:annotationDictionary document:documentRef];
                        
                        // if the type is recognized,
                        if (type != PSPDFAnnotationTypeUndefined) {
                            
                            // parses & normalizes "Rect" internally
                            PSPDFAnnotation *annotation = [[PSPDFAnnotation alloc] initWithPDFDictionary:annotationDictionary];
                            annotation.page = page;
                            annotation.document = self.document;
                            annotation.type = type;
                            
                            switch (type) {
                                case PSPDFAnnotationTypePage: {
                                    // parses target
                                    [self parsePageAnnotation:annotation dictionary:annotationDictionary document:documentRef];
                                } break;
                                    
                                case PSPDFAnnotationTypeHighlight: {
                                    // parse highlight annotation specific data
                                    [self parseHighlightAnnotation:annotation dictionary:annotationDictionary document:documentRef];                                    
                                } break;
                                    
                                default: {
                                    // annotation is PSPDFAnnotationTypeCustom, not our problem
                                } break;
                            }
                            
                            [newAnnotations addObject:annotation];
                        }
                    }
                }
            }
            
            // resolve external name references (only needed if name is saved in /GoTo page)
            NSDictionary *resolvedNames = [PSPDFOutlineParser resolveDestNames:[NSSet setWithArray:[namedDestinations_ allKeys]] documentRef:documentRef];
            for (NSNumber *destPageName in [resolvedNames allKeys]) {
                PSPDFAnnotation *annotation = [namedDestinations_ objectForKey:destPageName];
                if (annotation) {
                    NSInteger destPage = [[resolvedNames objectForKey:destPageName] integerValue];
                    annotation.pageLinkTarget = destPage;
                    annotation.type = PSPDFAnnotationTypeLink;
                }
            }
            
            dispatch_sync(dictCacheQueue_, ^{
                [pageCache_ setObject:newAnnotations forKey:pageNumber];
            });
            
            annotations = newAnnotations;
            [documentProvider releasePageRef:pageRef];
        }
    }
    
    // filter annotations
    NSMutableArray *filteredAnnotations = [NSMutableArray arrayWithCapacity:[annotations count]];
    BOOL addLinkAnnotations = filter & PSPDFAnnotationFilterLink;
    BOOL addOverlayAnnotations = filter & PSPDFAnnotationFilterOverlay;
    
    if (addLinkAnnotations && addOverlayAnnotations) {
        [filteredAnnotations addObjectsFromArray:annotations];
    }else {
        if (filter & PSPDFAnnotationFilterLink) {
            [filteredAnnotations addObjectsFromArray:[annotations filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.isOverlayAnnotation = NO"]]];
        }
        if (filter & PSPDFAnnotationFilterOverlay) {
            [filteredAnnotations addObjectsFromArray:[annotations filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.isOverlayAnnotation = YES"]]];
        }
    }
    
    return filteredAnnotations;
}

/// override to customize and support new url schemes.
- (void)parseAnnotationLinkTarget:(PSPDFAnnotation *)annotation {
    NSMutableString *link = [NSMutableString stringWithString:annotation.siteLinkTarget];
    
    if ([link hasPrefix:self.protocolString]) {
        // we both support a style like pspdfkit://www.xxx and pspdfkit://https://www.xxx 
        // for local files, use pspdfkit://localhost/Folder/File.ext
        [link deleteCharactersInRange:NSMakeRange(0, [self.protocolString length])];
        
        NSMutableDictionary *linkOptions = nil;
        NSString *pdfOptionMarker = @"%5B";
        NSString *optionEndMarker = @"%5D";
        if ([link hasPrefix:pdfOptionMarker]) {
            NSRange endRange = [link rangeOfString:optionEndMarker options:0 range:NSMakeRange([pdfOptionMarker length], [link length] - [pdfOptionMarker length])];
            if (endRange.length > 0) {
                NSString *optionStr = [link substringWithRange:NSMakeRange([pdfOptionMarker length], endRange.location - [pdfOptionMarker length])];
                [link deleteCharactersInRange:NSMakeRange(0, endRange.location + endRange.length)];
                
                // convert linkOptions to a dictionary
                NSArray *options = [optionStr componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":,"]];
                linkOptions = [NSMutableDictionary dictionary];
                NSUInteger optIndex = 0;
                while (optIndex+1 < [options count]) {
                    NSString *key = [options objectAtIndex:optIndex];
                    NSString *option = [options objectAtIndex:optIndex+1];
                    [linkOptions setObject:option forKey:key];
                    optIndex+=2;
                }
            }
        }
        if ([linkOptions count]) {
            annotation.options = linkOptions;
        }
        
        BOOL hasHttpInside = [link hasPrefix:@"http"];
        BOOL isLocalFile = [link hasPrefix:@"localhost"];
        if (!hasHttpInside && !isLocalFile) {
            [link insertString:@"http://" atIndex:0];
        }
        
        if (isLocalFile) {
            [link replaceOccurrencesOfString:@"localhost" withString:@"" options:0 range:NSMakeRange(0, [link length])];
            
            // replace Documents
            NSString *documentsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSUInteger replacements = [self replaceFirstOccurenceOfString:@"/Documents" withString:documentsDir mutableString:link];
            
            // replace Cache
            if (replacements == 0) {
                NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                replacements = [self replaceFirstOccurenceOfString:@"/Cache" withString:cachesDir mutableString:link];
            }
            
            // replace Bundle
            if (replacements == 0) {
                NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
                replacements = [self replaceFirstOccurenceOfString:@"/Bundle" withString:bundlePath mutableString:link];
                
                // if no replacements could be found, use local bundle
                if (replacements == 0) {
                    [link insertString:bundlePath atIndex:0];
                }
            }
            annotation.URL = [NSURL fileURLWithPath:link];
        }else {
            
            annotation.URL = [NSURL URLWithString:[link pspdf_escapedString]];
        }
        
        if ([link hasSuffix:@"m3u8"] || [link hasSuffix:@"mov"] ||
            [link hasSuffix:@"mpg"] || [link hasSuffix:@"avi"] || [link hasSuffix:@"m4v"]) {
            annotation.type = PSPDFAnnotationTypeVideo;
        }
        else if([link hasSuffix:@"mp3"] || [link hasSuffix:@"m4a"] || [link hasSuffix:@"mp4"]) {
            annotation.type = PSPDFAnnotationTypeAudio;
        }else if([link rangeOfString:@"youtube.com/"].length > 0) {
            annotation.type = PSPDFAnnotationTypeYouTube;
        }else if([link hasSuffix:@"jpg"] || [link hasSuffix:@"png"]  || [link hasSuffix:@"tiff"]|| [link hasSuffix:@"tif"] || [link hasSuffix:@"gif"]
                 || [link hasSuffix:@"bmp"] || [link hasSuffix:@"BMPf"] || [link hasSuffix:@"ico"] || [link hasSuffix:@"cur"] || [link hasSuffix:@"xbm"]) {
            annotation.type = PSPDFAnnotationTypeImage;
        }else {
            annotation.type = PSPDFAnnotationTypeBrowser;
            
            // check if we may want a link to an external browser window instead!
            if (annotation.isModal) {
                annotation.type = PSPDFAnnotationTypeLink;
            }
        }
        
        // force annotation to be of a specific type
        if ([[linkOptions objectForKey:@"type"] isKindOfClass:[NSString class]]) {
            NSString *manualType = [linkOptions objectForKey:@"type"];
            if ([manualType hasSuffix:@"video"]) {
                annotation.type = PSPDFAnnotationTypeVideo;
            }else if ([manualType hasSuffix:@"audio"]) {
                annotation.type = PSPDFAnnotationTypeAudio;
            }else if ([manualType hasSuffix:@"youtube"]) {
                annotation.type = PSPDFAnnotationTypeYouTube;
            }else if ([manualType hasSuffix:@"link"]) {
                annotation.type = PSPDFAnnotationTypeLink;
            }else if ([manualType hasSuffix:@"image"]) {
                annotation.type = PSPDFAnnotationTypeImage;
            }else if ([manualType hasSuffix:@"browser"]) {
                annotation.type = PSPDFAnnotationTypeBrowser;
            }else {
                PSPDFLogWarning(@"Unknown type specified: %@", manualType);
            }
        }
        
    }else if(![link hasPrefix:@"http"] && ![link hasPrefix:@"mailto:"]) {
        annotation.type = PSPDFAnnotationTypeCustom;        
    }else {
        annotation.type = PSPDFAnnotationTypeLink;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (NSUInteger)replaceFirstOccurenceOfString:(NSString *)string withString:(NSString *)newString mutableString:(NSMutableString *)mutableString {
    NSUInteger replacements = [mutableString replaceOccurrencesOfString:string withString:newString options:0 range:NSMakeRange(0, MIN([string length], [mutableString length]))];
    return  replacements;
}

- (PSPDFAnnotationType)annotationTypeForDictionary:(CGPDFDictionaryRef)annotationDictionary document:(CGPDFDocumentRef)documentRef {
    //identifies and validates the given annotation dictionary
    const char *annotationType;
    CGPDFDictionaryGetName(annotationDictionary, "Subtype", &annotationType);
    PSPDFAnnotationType type;
    
    // Link annotations are identified by Link name stored in Subtype key in annotation dictionary.
    if (strcmp(annotationType, "Link") == 0) {
        // as per previous commits
        type = PSPDFAnnotationTypePage;
        
    } else if (strcmp(annotationType, "Highlight") == 0) {
        type = PSPDFAnnotationTypeHighlight;
    } else {
        type = PSPDFAnnotationTypeUndefined;
    }
    
    return type;
}

- (void)parsePageAnnotation:(PSPDFAnnotation *)annotation dictionary:(CGPDFDictionaryRef)annotationDictionary document:(CGPDFDocumentRef)documentRef {
    // Link target can be stored either in A entry or in Dest entry in annotation dictionary.
    // Dest entry is the destination array that we're looking for. It can be a direct array definition
    // or a name. If it is a name, we need to search recursively for the corresponding destination array 
    // in document's Dests tree.
    // A entry is an action dictionary. There are many action types, we're looking for GoTo and URI actions.
    // GoTo actions are used for links within the same document. The GoTo action has a D entry which is the
    // destination array, same format like Dest entry in annotation dictionary.
    // URI actions are used for links to web resources. The URI action has a 
    // URI entry which is the destination URL.
    // If both entries are present, A entry takes precedence.
    
    CGPDFArrayRef destArray = NULL;
    CGPDFDictionaryRef actionDictionary = NULL;
    if (CGPDFDictionaryGetDictionary(annotationDictionary, "A", &actionDictionary)) {
        const char* actionType;
        if (CGPDFDictionaryGetName(actionDictionary, "S", &actionType)) {
            if (strcmp(actionType, "GoTo") == 0) {
                if(!CGPDFDictionaryGetArray(actionDictionary, "D", &destArray)) {
                    // D is not an array but a named reference?
                    CGPDFStringRef destNameRef;
                    if (CGPDFDictionaryGetString(actionDictionary, "D", &destNameRef)) {
                        const char *destNameCStr = (const char *)CGPDFStringGetBytePtr(destNameRef);
                        NSString *destinationName = [[NSString alloc] initWithCString:destNameCStr encoding:NSASCIIStringEncoding];                
                        [namedDestinations_ setObject:annotation forKey:destinationName];           
                    }
                }
            }
            if (strcmp(actionType, "URI") == 0) {
                CGPDFStringRef uriRef = NULL;
                if (CGPDFDictionaryGetString(actionDictionary, "URI", &uriRef)) {
                    const char *uri = (const char *)CGPDFStringGetBytePtr(uriRef);
                    annotation.siteLinkTarget = [[NSString alloc] initWithCString:uri encoding:NSASCIIStringEncoding];
                    [self parseAnnotationLinkTarget:annotation];
                }
            }
        }
    } else {
        // Dest entry can be either a string object or an array object.
        if (!CGPDFDictionaryGetArray(annotationDictionary, "Dest", &destArray)) {
            CGPDFStringRef destName;
            if (CGPDFDictionaryGetString(annotationDictionary, "Dest", &destName)) {
                // Traverse the Dests tree to locate the destination array.
                CGPDFDictionaryRef catalogDictionary = CGPDFDocumentGetCatalog(documentRef);
                CGPDFDictionaryRef namesDictionary = NULL;
                if (CGPDFDictionaryGetDictionary(catalogDictionary, "Names", &namesDictionary)) {
                    CGPDFDictionaryRef destsDictionary = NULL;
                    if (CGPDFDictionaryGetDictionary(namesDictionary, "Dests", &destsDictionary)) {
                        const char *destinationName = (const char *)CGPDFStringGetBytePtr(destName);
                        destArray = [self findDestinationByName: destinationName inDestsTree: destsDictionary];
                    }
                }
            }
        }
    }
    
    if (destArray != NULL) {
        int targetPageNumber = 0;
        // First entry in the array is the page the links points to.
        CGPDFDictionaryRef pageDictionaryFromDestArray = NULL;
        if (CGPDFArrayGetDictionary(destArray, 0, &pageDictionaryFromDestArray)) {
            int documentPageCount = CGPDFDocumentGetNumberOfPages(documentRef);
            for (int i = 1; i <= documentPageCount; i++) {
                CGPDFPageRef page = CGPDFDocumentGetPage(documentRef, i);
                CGPDFDictionaryRef pageDictionaryFromPage = CGPDFPageGetDictionary(page);
                if (pageDictionaryFromPage == pageDictionaryFromDestArray) {
                    targetPageNumber = i;
                    break;
                }
            }
        } else {
            // Some PDF generators use incorrectly the page number as the first element of the array 
            // instead of a reference to the actual page.
            CGPDFInteger pageNumber = 0;
            if (CGPDFArrayGetInteger(destArray, 0, &pageNumber)) {
                targetPageNumber = pageNumber + 1;
            }
        }
        
        if (targetPageNumber > 0) {
            annotation.pageLinkTarget = targetPageNumber;
            annotation.type = PSPDFAnnotationTypeLink;
        }
    }
}

- (void)parseHighlightAnnotation:(PSPDFAnnotation *)annotation dictionary:(CGPDFDictionaryRef)annotationDictionary document:(CGPDFDocumentRef)documentRef {
    //trying to figure out if anything needs to go here...
}

- (CGPDFArrayRef)findDestinationByName:(const char *)destinationName inDestsTree:(CGPDFDictionaryRef)node {
    CGPDFArrayRef destinationArray = NULL;
    CGPDFArrayRef limitsArray = NULL;
    
    // speed up search with respecting the limits table
    if (CGPDFDictionaryGetArray(node, "Limits", &limitsArray)) {
        CGPDFStringRef lowerLimit = NULL;
        CGPDFStringRef upperLimit = NULL;
        if (CGPDFArrayGetString(limitsArray, 0, &lowerLimit)) {
            if (CGPDFArrayGetString(limitsArray, 1, &upperLimit)) {
                const unsigned char *ll = CGPDFStringGetBytePtr(lowerLimit);
                const unsigned char *ul = CGPDFStringGetBytePtr(upperLimit);
                if ((strcmp(destinationName, (const char*)ll) < 0) ||
                    (strcmp(destinationName, (const char*)ul) > 0)) {
                    return NULL;
                }
            }
        }
    }
    
    CGPDFArrayRef namesArray = NULL;
    if (CGPDFDictionaryGetArray(node, "Names", &namesArray)) {
        int namesCount = CGPDFArrayGetCount(namesArray);
        for (int i = 0; i < namesCount; i = i + 2) {
            CGPDFStringRef destName;
            if (CGPDFArrayGetString(namesArray, i, &destName)) {
                const unsigned char *dn = CGPDFStringGetBytePtr(destName);
                if (strcmp((const char*)dn, destinationName) == 0) {
                    CGPDFDictionaryRef destinationDictionary = NULL;
                    if (CGPDFArrayGetDictionary(namesArray, i + 1, &destinationDictionary)) {
                        if (CGPDFDictionaryGetArray(destinationDictionary, "D", &destinationArray)) {
                            return destinationArray;
                        }
                    }
                }
            }
        }
    }
    
    CGPDFArrayRef kidsArray = NULL;
    if (CGPDFDictionaryGetArray(node, "Kids", &kidsArray)) {
        int kidsCount = CGPDFArrayGetCount(kidsArray);
        for (int i = 0; i < kidsCount; i++) {
            CGPDFDictionaryRef kidNode = NULL;
            if (CGPDFArrayGetDictionary(kidsArray, i, &kidNode)) {
                destinationArray = [self findDestinationByName: destinationName inDestsTree: kidNode];
                if (destinationArray != NULL) {
                    return destinationArray;
                }
            }
        }
    }
    
    return NULL;
}

@end


@implementation NSString (PSPDFAdditions)

- (NSString *)pspdf_escapedString {
    NSString *result = (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)self, NULL, CFSTR(" ()<>#{}|\\^~[]`;$"), kCFStringEncodingUTF8);
    return result;
}

@end
