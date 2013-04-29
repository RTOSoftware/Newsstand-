//
//  PSPDFSearchResult.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFSearchResult.h"
#import "Selection.h"

@implementation PSPDFSearchResult

@synthesize document = document_;
@synthesize pageIndex = pageIndex_;
@synthesize previewText = previewText_;
@synthesize selection = selection_;
@synthesize range = range_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)init {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
    document_ = nil;
}

- (NSString *)description {
    NSString *description = [NSString stringWithFormat:@"<PSPDFSearchResult page:%d selection:%@ previewText:%@>", pageIndex_, selection_, previewText_];
    return description;
}

- (NSUInteger)hash {
    return (([previewText_ hash] + range_.location * 31) + range_.length) * 31 + pageIndex_;
}

- (BOOL)isEqual:(id)other {
    if ([other isKindOfClass:[self class]]) {
        if (![self.previewText isEqual:[other previewText]] || !self.previewText || ![other previewText]
            || self.document != [other document]) {
            return NO;
        }
        return YES; 
    }
    else return NO;  
}

@end
