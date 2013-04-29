#import "CIDType2Font.h"
#import "PSPDFKit.h"

@implementation CIDType2Font

- (void)setCIDToGIDMapWithDictionary:(CGPDFDictionaryRef)dict
{
	CGPDFObjectRef object = nil;
	if (!CGPDFDictionaryGetObject(dict, "CIDToGIDMap", &object)) return;
	CGPDFObjectType type = CGPDFObjectGetType(object);
	if (type == kCGPDFObjectTypeName)
	{
		const char *mapName;
		if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeName, &mapName)) return;
		self.identity = YES;
	}
	else if (type == kCGPDFObjectTypeStream)
	{
		CGPDFStreamRef stream = nil;
		if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeStream, &stream)) return;
		NSData *data = (__bridge_transfer NSData *) CGPDFStreamCopyData(stream, nil);
		PSPDFLogWarning(@"CIDType2Font: no implementation for CID mapping with stream (%d bytes)", [data length]);
	}
}


- (void)setCIDSystemInfoWithDictionary:(CGPDFDictionaryRef)dict
{
	CGPDFDictionaryRef cidSystemInfo;
	if (!CGPDFDictionaryGetDictionary(dict, "CIDSystemInfo", &cidSystemInfo)) return;
    
	CGPDFStringRef registry;
	if (!CGPDFDictionaryGetString(cidSystemInfo, "Registry", &registry)) return;
    
	CGPDFStringRef ordering;
	if (!CGPDFDictionaryGetString(cidSystemInfo, "Ordering", &ordering)) return;
	
	CGPDFInteger supplement;
	if (!CGPDFDictionaryGetInteger(cidSystemInfo, "Supplement", &supplement)) return;
	
	NSString *registryString = (__bridge_transfer NSString *) CGPDFStringCopyTextString(registry);
	NSString *orderingString = (__bridge_transfer NSString *) CGPDFStringCopyTextString(ordering);
	
	NSString *cidSystemString = [NSString stringWithFormat:@"%@ (%@) %d", registryString, orderingString, supplement];
	PSPDFLogVerbose(@"%@", cidSystemString);
	
}

- (id)initWithFontDictionary:(CGPDFDictionaryRef)dict
{
	PSPDFLogVerbose(@"CID FONT TYPE 2");
	if ((self = [super initWithFontDictionary:dict]))
	{
		[self setCIDToGIDMapWithDictionary:dict];
		[self setCIDSystemInfoWithDictionary:dict];
	}
	return self;
}

- (NSString *)stringWithPDFString:(CGPDFStringRef)pdfString
{
    NSMutableString *result = nil;
	if (self.identity) {
        size_t length = CGPDFStringGetLength(pdfString);
        const unsigned char *cid = CGPDFStringGetBytePtr(pdfString);
        result = [[NSMutableString alloc] init];
//        NSData *data = [NSData dataWithBytes:cid length:length];
        for (int i = 0; i < length; i+=2) {
            unsigned char unicodeValue1 = cid[i];
            unsigned char unicodeValue2 = cid[i+1];
            unichar unicodeValue = (unicodeValue1 << 8) + unicodeValue2;
            [result appendFormat:@"%C", unicodeValue];
        }
    }
    return result;
}

@synthesize identity;
@end
