#import <Foundation/Foundation.h>
#import "StringDetector.h"
#import "FontCollection.h"
#import "RenderingState.h"
#import "Selection.h"

@interface Scanner : NSObject <StringDetectorDelegate> {
	NSURL *documentURL;
	NSString *keyword;
	CGPDFDocumentRef pdfDocument;
	CGPDFOperatorTableRef operatorTable;
	StringDetector *stringDetector;
	FontCollection *fontCollection;
	RenderingStateStack *renderingStateStack;
	Selection *currentSelection;
	NSMutableArray *selections;
	NSMutableString *rawTextContent;
}

/* Initialize with a file path */
- (id)initWithContentsOfFile:(NSString *)path;

/* Initialize with a PDF document */
- (id)initWithDocument:(CGPDFDocumentRef)document;

/* Start scanning (synchronous) */
- (void)scanDocumentPage:(NSUInteger)pageNumber;

/* Start scanning a particular page */
- (void)scanPage:(CGPDFPageRef)page;

@property (nonatomic, strong) NSMutableArray *selections;
@property (nonatomic, strong) RenderingStateStack *renderingStateStack;
@property (nonatomic, strong) FontCollection *fontCollection;
@property (nonatomic, strong) StringDetector *stringDetector;
@property (nonatomic, strong) NSString *keyword;
@property (nonatomic, strong) NSMutableString *rawTextContent;
@end
