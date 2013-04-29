#import <Foundation/Foundation.h>
#import "PSPDFKitGlobal.h"
#import "Font.h"

@interface FontCollection : NSObject {
	NSMutableDictionary *fonts;
	NSArray *names;
}

/* Initialize with a font collection dictionary */
- (id)initWithFontDictionary:(CGPDFDictionaryRef)dict;

/* Return the specified font */
- (Font *)fontNamed:(NSString *)fontName;

@property (ps_weak, nonatomic, readonly) NSDictionary *fontsByName;

@property (nonatomic, readonly) NSArray *names;

@end
