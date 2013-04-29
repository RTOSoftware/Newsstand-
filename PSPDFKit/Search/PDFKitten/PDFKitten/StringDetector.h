/*
 *	Given a keyword and a stream of charachers, triggers when
 *	the desired needle is found.
 *
 *	The implementation ressembles a finite state machine (FSM).
 *
 *
 */

#import "PSPDFKitGlobal.h"
#import "Font.h"

@class StringDetector;

@protocol StringDetectorDelegate <NSObject>

@optional

/* Tells the delegate that the first character of the needle was detected */
- (void)detector:(StringDetector *)detector didStartMatchingString:(NSString *)string;

/* Tells the delegate that the entire needle was detected */
- (void)detector:(StringDetector *)detector foundString:(NSString *)needle;

/* Tells the delegate that one character was scanned */
- (void)detector:(StringDetector *)detector didScanCharacter:(unichar)character;

@end


@interface StringDetector : NSObject {
	NSString *keyword;
	NSUInteger keywordPosition;
	NSMutableString *unicodeContent;
	id<StringDetectorDelegate> __ps_weak delegate;
}

/* Initialize with a given needle */
- (id)initWithKeyword:(NSString *)needle;

/* Feed more charachers into the state machine */
- (NSString *)appendPDFString:(CGPDFStringRef)string withFont:(Font *)font;

/* Reset the detector state */
- (void)reset;

@property (nonatomic, strong) NSString *keyword;
@property (nonatomic, ps_weak) id<StringDetectorDelegate> delegate;
@property (ps_weak, nonatomic, readonly) NSString *unicodeContent;
@end
