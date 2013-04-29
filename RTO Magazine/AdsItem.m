//
//  AdsItem.m
//  NAFA Magazine
//
//  Created by JangWu on 5/15/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "AdsItem.h"

@implementation AdsItem
@synthesize thumbImage;
@synthesize bigImage;
@synthesize linkUrl;
-(id)init{
    self = [super init];
    if(self){
        thumbImage = [[UIImage alloc] init];
        bigImage = [[UIImage alloc] init];
        linkUrl = [[NSString alloc] init];
    }
    return self;
}
-(void)dealloc{
    [thumbImage release];
    [bigImage release];
    [linkUrl release];
    [super dealloc];
}
@end
