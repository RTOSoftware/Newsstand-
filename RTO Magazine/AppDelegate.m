//
//  AppDelegate.m
//  PSPDFKitExample
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "AppDelegate.h"
#import "PSPDFGridController.h"
#import "PSPDFSettingsController.h"
#import "SDURLCache.h"
#import "NSObject+SBJSON.h"
#import "NSString+SBJSON.h"
// can also be read from Info.plist, etc...
#define kAppVersionKey @"AppVersion"
#define kAppVersion 17

@implementation AppDelegate

@synthesize window = window_;
@synthesize LgridController;
@synthesize pushnotificationtype;
@synthesize message;
@synthesize isMessage;
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// it's advised to clear the cache before updating PSPDFKit.
- (void)clearCacheOnUpgrade
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:kAppVersionKey] < kAppVersion)
    {
        NSLog(@"clearing cache because of new install/upgrade.");
        [[PSPDFCache sharedPSPDFCache] clearCache]; // thread-safe.
        
        // save new version number
        [[NSUserDefaults standardUserDefaults] setInteger:kAppVersion forKey:kAppVersionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

// this is an example how to override the few keywords in PSPDFKit.
// you can also change the contents of the PSPDFKit.bundle, but you need to re-do this after every update
- (void)addCustomLocalization
{
    // prepare the dictionary structure (here, we only add en, which is the fallback)
    NSMutableDictionary *localizationDict = [NSMutableDictionary dictionaryWithCapacity:1];
    NSMutableDictionary *enLocalizationDict = [NSMutableDictionary dictionaryWithCapacity:1];
    [localizationDict setObject:enLocalizationDict forKey:@"en"];
    
    // add localization content
    [enLocalizationDict setObject:@"Magazines" forKey:@"Documents"];
    PSPDFSetLocalizationDictionary(localizationDict);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // setup disk saving url cache
    SDURLCache *URLCache = [[SDURLCache alloc] initWithMemoryCapacity:1024*1024   // 1MB mem cache
                                                         diskCapacity:1024*1024*5 // 5MB disk cache
                                                             diskPath:[SDURLCache defaultCachePath]];
    [NSURLCache setSharedURLCache:URLCache];
    
    [[PSPDFCache sharedPSPDFCache] clearCache];
    
    // uncomment to enable PSPDFKitLogging. Defaults to PSPDFLogLevelError
    
    kPSPDFLogLevel = PSPDFLogLevelInfo;
    
    //kPSPDFLogLevel = PSPDFLogLevelVerbose;
    
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    PSPDFLog(@"Kiosk Example %@ is starting up... [PSPDFKit Version %@]", appVersion, PSPDFVersionString());
    
    // enable to see the scrollviews semi-transparent
    //kPSPDFKitDebugScrollViews = YES;
    
    // enable to see memory usage
    //kPSPDFKitDebugMemory = YES;
    
    // enable to change anomations (e.g. enable on iPad1)
    
    kPSPDFAnimateOption = PSPDFAnimateEverywhere;
    
    // setup device specific defaults
    
    [PSPDFSettingsController setupDefaults];
    
    // add custom localization changes
    
    [self addCustomLocalization];
    
    // check if system was updated to iOS 5.0.1 or higher to migrate data (iCloud Backup issue)
    // WARNING. This should be done async instead - be careful if you hava a large dataset.
    // See https://developer.apple.com/library/ios/#qa/qa1719/_index.html
    
    BOOL migrated = [PSPDFStoreManager checkAndIfNeededMigrateStoragePathBlocking:YES completionBlock:nil];
    if (migrated)
    {
        PSPDFLog(@"Just migrated storage data.");
    }
    
    // create main grid and show!
    
    
    LgridController = [[PSPDFGridController alloc] init];
    
    //window_ = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    //[window_ makeKeyAndVisible];
//    UITabBarController *tabBar = (UITabBarController*)self.window.rootViewController;
//    NSMutableArray *viewControllers = [[NSMutableArray alloc] init];
    
    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:LgridController];
    window_.rootViewController = nav1;
    
//    
//    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:nil];
//    UINavigationController *nav2 = [storyboard instantiateViewControllerWithIdentifier:@"OfferNav"];
//    [viewControllers addObject:nav1];
//    [viewControllers addObject:nav2];
//    [viewControllers addObject:nav3];

//    [tabBar setViewControllers:viewControllers];
    
    NSString *cacheFolder = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    PSELog(@"CacheDir: %@", cacheFolder);
    
    // set white status bar style when not on ipad
    
    if (!PSIsIpad()) {
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:NO];
    }
    
    // after a version upgrade, reset the cache
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [self clearCacheOnUpgrade];
    });
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Subscribe" message:@"Would you like to activate your free subscription to NAFA Annuity Outlook Magazine?" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:@"Cancel", nil];
    [alert show];
    [alert release];
    if([[defaults objectForKey:@"subscribe"]boolValue]||[[defaults objectForKey:@"message"]boolValue])
    {
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeNewsstandContentAvailability|UIRemoteNotificationTypeAlert|UIRemoteNotificationTypeBadge];
    }
    return YES;
}

-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if(buttonIndex == 0)
    {
        [defaults setBool:YES forKey:@"Subscription"];
    }
    else
    {
        [defaults setBool:NO forKey:@"Subscription"];
    }
    [defaults synchronize];
}

-(void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    if([[userInfo objectForKey:@"notifytype"] isEqualToString:@"message"])
    {
        message = [userInfo objectForKey:@"content"];
        isMessage = TRUE;
    }
    else
    {
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
    }
}

-(void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
//    [FlurryAnalytics setLatitude:newLocation.coordinate.latitude longitude:newLocation.coordinate.longitude horizontalAccuracy:newLocation.horizontalAccuracy verticalAccuracy:newLocation.verticalAccuracy];
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if(![[defaults objectForKey:@"RegisterDeviceToken"]boolValue])
    {
        NSURLRequest *urlrequest = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://annuityoutlookmagazine.com/nafa/service.php?action=registerDeviceToken&token=%@",deviceToken]]];
        NSURLConnection *urlConnection = [[NSURLConnection alloc] initWithRequest:urlrequest delegate:self];
        [urlConnection start];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSString* responseString = [[[NSString alloc] initWithData:_downloadedData
                                                      encoding:NSUTF8StringEncoding]
                                autorelease];
    NSDictionary *dict = (NSDictionary*)[responseString JSONValue];
    if([[dict objectForKey:@"success"] isEqualToString:@"true"]){
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:@"RegisterDeviceToken"];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    //This function is called when the download begins.
    //You can get all the response headers
    if (_downloadedData!=nil) {
        [_downloadedData release];
        _downloadedData = nil;
    }
    _downloadedData = [[NSMutableData alloc] init];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    //This function is called whenever there is downloaded data available
    //It will be called multiple times and each time you will get part of downloaded data
    [_downloadedData appendData:data];
}
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error
{
	NSLog(@"Failed to get token, error: %@", error);
}
@end
