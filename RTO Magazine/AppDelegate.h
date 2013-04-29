#define kPSPDFExampleDebugEnabled

// ARC is compatible with iOS 4.0 upwards, but you need at least Xcode 4.2 with Clang LLVM 3.0 to compile it.
#if !defined(__clang__) || __clang_major__ < 3
#error This project must be compiled with ARC (Xcode 4.2+ with LLVM 3.0 and above)
#endif

// uncomment to try out QuickLook instead of PSPDFKit
//#define kPSPDFQuickLookEngineEnabled

#ifdef kPSPDFExampleDebugEnabled
#define PSELog(fmt, ...) NSLog((@"%s/%d " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#define PSELog(...)
#endif

#define _(s) NSLocalizedString(s,s)
#define XAppDelegate ((AppDelegate *)[[UIApplication sharedApplication] delegate])

//#define kPSPDFMagazineJSONURL @"http://pspdfkit.com/magazines.json"
#define kPSPDFMagazineJSONURL @"http://annuityoutlookmagazine.com/nafa/issue.json"
#define kPSPDFAdsJSONURL @"http://annuityoutlookmagazine.com/nafa/service.php?action=ads.json&issueID=6"
#define kregisterDeviceToken @"http://annuityoutlookmagazine.com/nafa/service.php?action=registerDeviceToken&token=%@"
#import <CoreLocation/CoreLocation.h>
@class PSPDFGridController;

@interface AppDelegate : UIResponder <UIApplicationDelegate,NSURLConnectionDelegate,CLLocationManagerDelegate,UIAlertViewDelegate>
{
    PSPDFGridController *gridController_;
    UIWindow *window_;
    NSMutableData *_downloadedData;
}

@property (nonatomic, strong) IBOutlet UIWindow *window;
@property (nonatomic, retain) PSPDFGridController *LgridController;
@property (nonatomic, retain) NSString* pushnotificationtype;
@property (nonatomic, retain) NSString* message;
@property (nonatomic) BOOL isMessage;
@end
