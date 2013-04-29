#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CMap : NSObject {
	NSMutableArray *offsets;
    NSMutableDictionary *chars;
}

/* Initialize with PDF stream containing a CMap */
- (id)initWithPDFStream:(CGPDFStreamRef)stream;

/* Unicode mapping for character ID */
- (NSString *)unicodeCharacter:(unichar)cid;

- (unichar)cidCharacter:(unichar)unicode;

@end
