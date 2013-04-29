//
//  SecondViewController.h
//  NAFA Magazine
//
//  Created by JangWu on 5/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//
#define kPSPDFAdsJSONURLCustom @"http://annuityoutlookmagazine.com/nafa/service.php?action=ads.json&issueID=%@"
#import <UIKit/UIKit.h>

@interface OfferViewController : UIViewController<NSURLConnectionDelegate,UITableViewDataSource,UITableViewDelegate>{
    NSMutableData *_downloadedData;
}
@property (retain, nonatomic) IBOutlet UIImageView *imgLogo;

@property (retain, nonatomic) IBOutlet UIImageView *imgView;
@property (retain, nonatomic) IBOutlet UIScrollView *pscrollView;
@property (retain, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (retain, nonatomic) NSMutableArray *AdsList;
@property (retain, nonatomic) NSURLConnection *connection;
@property (retain, nonatomic) UIWebView *webView;
@property (retain, nonatomic) IBOutlet UITableView *tblList;
@property (retain, nonatomic) NSMutableArray *magazineList;
- (void)gestureView:(id)sender;
- (void)imgViewSelected:(UITapGestureRecognizer*)gesture;
@end
