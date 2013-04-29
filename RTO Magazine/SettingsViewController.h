//
//  SettingsViewController.h
//  NAFA Magazine
//
//  Created by JangWu on 5/15/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>
#define kViewTag				1
@interface SettingsViewController : UIViewController<UITableViewDataSource, UITableViewDelegate,MFMailComposeViewControllerDelegate,NSURLConnectionDelegate>
@property (retain, nonatomic) IBOutlet UITableView *contentTable;
@property (nonatomic, retain) NSMutableArray *dataSourceArray;
@property (nonatomic, retain, readonly) UISwitch *switchCtl;
@property (nonatomic, retain) UITableView *tblView;
- (IBAction)actInfo:(id)sender;
- (IBAction)actPrivacy:(id)sender;
- (IBAction)messageOn:(id)sender;
@property (retain, nonatomic) IBOutlet UISwitch *switchSubscribe;
@property (retain, nonatomic) IBOutlet UISwitch *switchMessage;

- (IBAction)SubscribeOn:(id)sender;
- (UISwitch *)switchCtl:(NSInteger)index;
@end
