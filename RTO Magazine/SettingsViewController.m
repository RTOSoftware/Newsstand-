//
//  SettingsViewController.m
//  NAFA Magazine
//
//  Created by JangWu on 5/15/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "SettingsViewController.h"

static NSString *kSourceKey = @"sourceKey";
static NSString *kViewKey = @"viewKey";
static NSString *kSectionTitleKey = @"sectionTitleKey";
static NSString *kLabelKey = @"labelKey";
static NSString *kTagKey = @"tagKey";
@implementation SettingsViewController
@synthesize switchSubscribe;
@synthesize switchMessage;
@synthesize contentTable;
@synthesize dataSourceArray;
@synthesize switchCtl;
@synthesize tblView;
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

/*
// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView
{
}
*/


// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidAppear:(BOOL)animated{

}
- (void)viewDidLoad
{
    self.contentSizeForViewInPopover = CGSizeMake(280, 600);
    [self.contentTable setFrame:CGRectMake(10, 10, 180, 300)];

    self.dataSourceArray = [NSMutableArray arrayWithObjects:
							[NSDictionary dictionaryWithObjectsAndKeys:
                             @"Subscription", kSectionTitleKey,
                             @"Subscription", kLabelKey,
                             @"Off for don't subscript any more.", kSourceKey,
                             self.switchCtl, kViewKey,
                             1,kTagKey,
							 nil],
                            
							[NSDictionary dictionaryWithObjectsAndKeys:
                             @"Downloads", kSectionTitleKey,
                             @"Restore Downloads", kLabelKey,
                             @"On for restore old issues.", kSourceKey,
                             self.switchCtl, kViewKey,
                             2,kTagKey,
							 nil],
							
							[NSDictionary dictionaryWithObjectsAndKeys:
                             @"Messages", kSectionTitleKey,
                             @"Messages", kLabelKey,
                             @"On for receive messages from publish,partners,new issues.", kSourceKey,
                             self.switchCtl, kViewKey,
                             3,kTagKey,
							 nil],
                            
							nil];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSLog(@"%@",[defaults objectForKey:@"Subscription"]);
    NSLog(@"%@",[defaults objectForKey:@"Messages"]);
    if([defaults objectForKey:@"Subscription"]){
        BOOL b = [[defaults objectForKey:@"Subscription"]boolValue];
        switchSubscribe.on = b;
    }else{
        switchSubscribe.on = YES;
    }
    if([defaults objectForKey:@"Messages"]){
        BOOL b = [[defaults objectForKey:@"Messages"]boolValue];
        switchMessage.on = b;
    }else{
        switchMessage.on = YES;
    }
    
    [super viewDidLoad];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return [self.dataSourceArray count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return [[self.dataSourceArray objectAtIndex: section] valueForKey:kSectionTitleKey];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return 2;
}

// to determine specific row height for each cell, override this.
// In this example, each row is determined by its subviews that are embedded.
//
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return ([indexPath row] == 0) ? 50.0 : 38.0;
}

// to determine which UITableViewCell to be used on a given row.
//
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = nil;
    
	if ([indexPath row] == 0)
	{
		static NSString *kDisplayCell_ID = @"DisplayCellID";
		cell = [self.contentTable dequeueReusableCellWithIdentifier:kDisplayCell_ID];
        if (cell == nil)
        {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kDisplayCell_ID] autorelease];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		else
		{
			// the cell is being recycled, remove old embedded controls
			UIView *viewToRemove = nil;
			viewToRemove = [cell.contentView viewWithTag:kViewTag];
			if (viewToRemove)
				[viewToRemove removeFromSuperview];
		}
		
		cell.textLabel.text = [[self.dataSourceArray objectAtIndex: indexPath.section] valueForKey:kLabelKey];
		CGRect frame = CGRectMake(198.0, 12.0, 94.0, 27.0);
        switchCtl = [[UISwitch alloc] initWithFrame:frame];
        [switchCtl addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
        
        // in case the parent view draws with a custom color or gradient, use a transparent color
        switchCtl.backgroundColor = [UIColor clearColor];
        
        [switchCtl setAccessibilityLabel:NSLocalizedString(@"StandardSwitch", @"")];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSLog(@"%@",[[self.dataSourceArray objectAtIndex:indexPath.section] objectForKey:kLabelKey]);
        if([defaults objectForKey:[[self.dataSourceArray objectAtIndex:indexPath.section] objectForKey:kLabelKey]]){
            NSLog(@"exist");
        }else{
            [defaults setBool:YES forKey:[[self.dataSourceArray objectAtIndex:indexPath.section] objectForKey:kLabelKey]];
        }
        switchCtl.tag = indexPath.section;
        NSLog(@"%d",switchCtl.tag);
        BOOL b = [[defaults objectForKey:[[self.dataSourceArray objectAtIndex: indexPath.section] valueForKey:kLabelKey]]boolValue];
        switchCtl.on = b;
		//UIControl *control = [[self.dataSourceArray objectAtIndex: indexPath.section] valueForKey:kViewKey];
		[cell.contentView addSubview:switchCtl];
	}
	else
	{
		static NSString *kSourceCellID = @"SourceCellID";
		cell = [self.contentTable dequeueReusableCellWithIdentifier:kSourceCellID];
        if (cell == nil)
        {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSourceCellID] autorelease];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			
			cell.textLabel.opaque = NO;
            cell.textLabel.textAlignment = UITextAlignmentCenter;
            cell.textLabel.textColor = [UIColor grayColor];
			cell.textLabel.numberOfLines = 2;
			cell.textLabel.highlightedTextColor = [UIColor blackColor];
            cell.textLabel.font = [UIFont systemFontOfSize:12.0];	
        }
		
		cell.textLabel.text = [[self.dataSourceArray objectAtIndex: indexPath.section] valueForKey:kSourceKey];
	}
    
	return cell;
}
- (void)switchAction:(id)sender
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UISwitch *switchcontrol = (UISwitch*)sender;
    NSLog(@"%d",switchcontrol.tag);
    if(switchcontrol.tag == 0){
        BOOL b = [[defaults objectForKey:@"Subscription"]boolValue];
        [defaults setBool:!b forKey:@"Subscription"];
    }else if(switchcontrol.tag == 2){
        BOOL b = [[defaults objectForKey:@"Messages"]boolValue];
        [defaults setBool:!b forKey:@"Messages"];
    }else if(switchcontrol.tag == 1){
        BOOL b = [[defaults objectForKey:@"Restore"]boolValue];
        [defaults setBool:!b forKey:@"Restore"];
    }
    [defaults synchronize];
	// NSLog(@"switchAction: value = %d", [sender isOn]);
}
- (IBAction)actInfo:(id)sender {
    if ([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController* controller = [[MFMailComposeViewController alloc] init];
        controller.mailComposeDelegate = self;
        [controller setSubject:@"Subject"];
        [controller setMessageBody:@"Write something here." isHTML:NO]; 
        [controller setToRecipients:[NSArray arrayWithObjects:[NSString stringWithString:@"info@annuityoutlookmagazine.com"], nil]];
        if (controller) [self presentModalViewController:controller animated:YES];
        [controller release];
    } else {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"You cannot email at the moment." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [alert show];
        [alert release];
    }
    
}
- (void)mailComposeController:(MFMailComposeViewController*)controller  
          didFinishWithResult:(MFMailComposeResult)result 
                        error:(NSError*)error;
{
    if (result == MFMailComposeResultSent) {
        NSLog(@"It's away!");
    }
    [self dismissModalViewControllerAnimated:YES];
}
-(void)dismissWebView:(id)sender{
    UIWebView *w = (UIWebView*) [self.view viewWithTag:100];
    [w removeFromSuperview];
    [sender removeFromSuperview];
}
- (IBAction)actPrivacy:(id)sender {
    UIWebView *aWebView = [[[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 280, 600)] autorelease];//init and create the UIWebView
    aWebView.autoresizesSubviews = YES;
    aWebView.autoresizingMask=(UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
    //set the web view delegates for the web view to be itself
    //[aWebView setDelegate:self];
    //Set the URL to go to for your UIWebView
    NSString *urlAddress = @"http://annuityoutlookmagazine.com/privacy-policy/";
    //Create a URL object.
    NSURL *url = [NSURL URLWithString:urlAddress];
    //URL Requst Object
    NSURLRequest *requestObj = [NSURLRequest requestWithURL:url];
    //load the URL into the web view.
    [aWebView loadRequest:requestObj];
    //add the web view to the content view
    aWebView.tag = 100;
    [self.view addSubview:aWebView];
    
    UIButton *bb = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *img = [UIImage imageNamed:@"back.png"];
    [bb setImage:img forState:UIControlStateNormal];
    [img release];
    [bb addTarget:self 
           action:@selector(dismissWebView:) forControlEvents:UIControlEventTouchDown];
                            [bb setTitle:@"Back" forState:UIControlStateNormal];
                            bb.frame = CGRectMake(230, 0.0, 60.0, 30.0);
                            [self.view addSubview:bb];
}

- (IBAction)messageOn:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL b = [[defaults objectForKey:@"Messages"]boolValue];
    [defaults setBool:!b forKey:@"Messages"];
    [defaults synchronize];
}

- (IBAction)SubscribeOn:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL b = [[defaults objectForKey:@"Subscription"]boolValue];
    [defaults setBool:!b forKey:@"Subscription"];
    [defaults synchronize];
}

- (UISwitch *)switchCtl:(NSInteger)index
{
    if (switchCtl == nil) 
    {
        CGRect frame = CGRectMake(27.0*index, 12.0, 94.0, 27.0);
        switchCtl = [[UISwitch alloc] initWithFrame:frame];
        [switchCtl addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
        
        // in case the parent view draws with a custom color or gradient, use a transparent color
        switchCtl.backgroundColor = [UIColor clearColor];
		
		[switchCtl setAccessibilityLabel:NSLocalizedString(@"StandardSwitch", @"")];
		
		switchCtl.tag = kViewTag;	// tag this view for later so we can remove it from recycled table cells
    }
    return switchCtl;
}

- (void)viewDidUnload
{
    [self setContentTable:nil];
    self.dataSourceArray = nil;
    [self setSwitchSubscribe:nil];
    [self setSwitchMessage:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)dealloc {
    [tblView release];
    [contentTable release];
    [switchSubscribe release];
    [switchMessage release];
    [super dealloc];
}
@end
