//
//  PSPDFOutlineElement.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKitGlobal.h"
#import "PSPDFOutlineElement.h"

@implementation PSPDFOutlineElement

@synthesize title = title_;
@synthesize page = page_;
@synthesize children = children_;
@synthesize level = level_;
@synthesize expanded = expanded_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithTitle:(NSString *)title page:(NSUInteger)page elements:(NSArray *)elements level:(NSUInteger)level {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        title_ = [title copy];
        page_ = page;
        level_ = level;
        children_ = [elements copy];
    }
    return self;
}

- (void)dealloc {
    PSPDFDeregisterObject(self);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<PSPDFOutlineElement title:%@ page:%d level:%d childCount:%d, children:%@>", self.title, self.page, self.level, [self.children count], self.children];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)addOpenChildren:(NSMutableArray *)list {
	[list addObject:self];
	if (expanded_) {
		for (PSPDFOutlineElement *child in children_) {
			[child addOpenChildren:list];
		}
	}
}

- (NSArray *)flattenedChildren {
	NSMutableArray *flatList = [NSMutableArray array];
	for (PSPDFOutlineElement *child in children_) {
		[child addOpenChildren:flatList];
	}
	return [flatList copy];
}

@end
