//
//  SecondViewController.m
//  NAFA Magazine
//
//  Created by JangWu on 5/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "OfferViewController.h"
#import "AdsItem.h"
#import "AFJSONRequestOperation.h"
#import "NSOperationQueue+CWSharedQueue.h"
#import "NSObject+SBJSON.h"
#import "NSString+SBJSON.h"
#import "AppDelegate.h"
#import "PSPDFGridController.h"
#import "PSPDFMagazineFolder.h"
#import "PSPDFMagazine.h"
const CGFloat kScrollObjHeight	= 180.0;
const CGFloat kScrollObjWidth	= 200.0;
@implementation OfferViewController
@synthesize imgLogo;
@synthesize imgView;
@synthesize pscrollView;
@synthesize activityIndicator;
@synthesize AdsList;
@synthesize connection;
@synthesize webView;
@synthesize tblList;
@synthesize magazineList;
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle
- (void)layoutScrollImages:(UIScrollView*)scrollView
{
	UIView *view = nil;
	NSArray *subviews = [scrollView subviews];
    
	// reposition all image subviews in a horizontal serial fashion
	CGFloat curXLoc = 30;
    //CGFloat lastWidth = 0;
	for (view in subviews)
	{
		if ([view isKindOfClass:[UIView class]] && view.tag > 0)
		{
			CGRect frame = view.frame;
			frame.origin = CGPointMake(curXLoc, 5);
			view.frame = frame;
			
			curXLoc += (view.frame.size.width+10);
            //lastWidth = view.frame.size.width;
		}
	}
	// set the content size so it can be scrollable
	[scrollView setContentSize:CGSizeMake(curXLoc + 30, [scrollView bounds].size.height)];

}
- (void)viewSelected:(UITapGestureRecognizer*)gesture{
    AdsItem *item = [AdsList objectAtIndex:gesture.view.tag-1];
    [imgView setImage:item.bigImage];
    imgView.tag = gesture.view.tag-1;
    imgView.bounds = CGRectMake(0, 0, item.bigImage.size.width, item.bigImage.size.height);
    webView.hidden = YES;
}
- (void)gestureView:(id)sender {
    if(tblList.frame.size.width == 0){
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:1];
        [tblList setFrame:CGRectMake(0, 100, 130, 630)];
        [tblList setAlpha:1];
        [UIView commitAnimations];
    }else{
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:1];
        [tblList setFrame:CGRectMake(0, 100, 0, 630)];
        [tblList setAlpha:0];
        [UIView commitAnimations];
    }
}

- (void)imgViewSelected:(UITapGestureRecognizer*)gesture{
    AdsItem *item = [AdsList objectAtIndex:imgView.tag];
    webView.hidden = NO;
    [webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:item.linkUrl]]];
    
}
-(void)configureScroll{
    UIView *view = nil;
	NSArray *subviews = [pscrollView subviews];
    
	// reposition all image subviews in a horizontal serial fashion
	for (view in subviews)
	{
		if ([view isKindOfClass:[UIView class]] && view.tag > 0)
		{
			[view removeFromSuperview];
            //lastWidth = view.frame.size.width;
		}
	}
    [pscrollView setCanCancelContentTouches:NO];
    pscrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    pscrollView.clipsToBounds = YES;		// default is NO, we want to restrict drawing within our scrollview
    pscrollView.scrollEnabled = YES;
    
    // pagingEnabled property default is NO, if set the scroller will stop or snap at each photo
    // if you want free-flowing scroll, don't set this property.
    
    
    for(AdsItem *item in AdsList){
        UIView *itemView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, item.thumbImage.size.width+20, item.thumbImage.size.height+20)];
        UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewSelected:)];
        UIImage *image = item.thumbImage;
        
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        CGRect rect = imageView.frame;
        rect.origin = CGPointMake(10, 10);
        //rect.size.height = kScrollObjHeight;
        //rect.size.width = kScrollObjWidth;
        rect.size.height = image.size.height;
        rect.size.width = image.size.width;
        imageView.frame = rect;
        
        itemView.tag = [AdsList indexOfObject:item]+1;	// tag our images for later use when we place them in serial fashion
        [itemView addSubview:imageView];
        [itemView setBackgroundColor:[UIColor colorWithRed:1 green:1 blue:1 alpha:0.3]];
        [pscrollView addSubview:itemView];
        [itemView addGestureRecognizer:gestureRecognizer];
        [gestureRecognizer release];
        [imageView release];
        [itemView release];
    }
    AdsItem *it = [AdsList objectAtIndex:0];
    [imgView setImage:it.bigImage];
    imgView.bounds = CGRectMake(0, 0, it.bigImage.size.width, it.bigImage.size.height);
    imgView.tag = 0;
    [self layoutScrollImages:pscrollView];
    imgView.userInteractionEnabled = YES;
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imgViewSelected:)];
    [imgView addGestureRecognizer:gestureRecognizer];
    [gestureRecognizer release];
    
}
- (id)parseJsonResponse:(NSData *)data error:(NSError **)errorA {
    
    NSString* responseString = [[[NSString alloc] initWithData:data
                                                      encoding:NSUTF8StringEncoding]
                                autorelease];
    return [responseString JSONValue];
}
- (void)handleResponseData:(NSData *)data {
    NSError* errorA = nil;
    id result = [self parseJsonResponse:data error:&errorA];
    NSArray *adsResult = (NSArray*)result;
    if([adsResult count] != 0){
        if(AdsList == nil){
            AdsList = [[NSMutableArray alloc] init];
        }else{
            [AdsList removeAllObjects];
        }
        for(NSDictionary *dict in adsResult){
            AdsItem *ads = [[AdsItem alloc] init];
            [ads setLinkUrl:[dict objectForKey:@"url"]];
            [ads setBigImage:[UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@",[dict objectForKey:@"Img"]]]]]];
            [ads setThumbImage:[UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@",[dict objectForKey:@"Thumbnail"]]]]]];
            [AdsList addObject:ads];
            [ads release];
        }
        [self configureScroll];
    }else{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Message" message:@"There's no advertisment of this issue." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [alert show];
        [alert release];
    }
    [activityIndicator stopAnimating];
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response{
    //This function is called when the download begins.
    //You can get all the response headers
    if (_downloadedData!=nil) {
        [_downloadedData release];
        _downloadedData = nil;
    }
    _downloadedData = [[NSMutableData alloc] init];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{
    //This function is called whenever there is downloaded data available
    //It will be called multiple times and each time you will get part of downloaded data
    [_downloadedData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection{
    //This function is called once the download is complete
    //The next step is parse the downloaded xml feed
    [self handleResponseData:_downloadedData];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    //
}

- (void)viewDidLoad
{
    AppDelegate *app = (AppDelegate*)[[UIApplication sharedApplication] delegate];
    magazineList = [[NSMutableArray alloc] initWithArray:app.LgridController.magazineFolder.magazines];
    webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 97, 768, 646)];
    
    // allow inline playback, even on iPhone
    [self.view addSubview:webView];
    webView.hidden = YES;
    //self.navigationController.navigationBarHidden = YES;
    [activityIndicator setHidden:YES];
    
    [super viewDidLoad];
    
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gestureView:)];
    [gestureRecognizer setNumberOfTapsRequired:2];
    [self.view addGestureRecognizer:gestureRecognizer];
    [gestureRecognizer release];
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDelay:0.5];
    [tblList setFrame:CGRectMake(0, 100, 130, 720)];
    [UIView commitAnimations];
	// Do any additional setup after loading the view, typically from a nib.
    
}
-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    PSPDFMagazine *magazine = [magazineList objectAtIndex:indexPath.row];
    cell.textLabel.text = magazine.title;
    //[cell.imageView setImage:[UIImage imageWithData:[NSData dataWithContentsOfURL:magazine.imageUrl]]];
    //NSLog(@"%@",magazine.issueId);
    return cell;
}
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    PSPDFMagazine *magazine = [magazineList objectAtIndex:indexPath.row];
    NSURL *url = [[[NSURL alloc] initWithString:[NSString stringWithFormat:kPSPDFAdsJSONURLCustom,magazine.issueId]] autorelease];
    NSURLRequest *urlrequest = [[[NSURLRequest alloc] initWithURL:url] autorelease];
    connection = [[NSURLConnection alloc] initWithRequest:urlrequest delegate:self];
    [activityIndicator setHidden:NO];
    [activityIndicator startAnimating];
    activityIndicator.hidesWhenStopped = YES;
    [self gestureView:nil];
}
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return [self.magazineList count];
}
- (void)viewDidUnload
{
    [self setImgView:nil];
    [self setPscrollView:nil];
    [self setActivityIndicator:nil];
    [self setConnection:nil];
    [self setAdsList:nil];
    [self setTblList:nil];
    [self setMagazineList:nil];
    [self setImgLogo:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}
-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration{
    if(toInterfaceOrientation == UIInterfaceOrientationPortrait || toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown){
        [imgLogo setImage:[UIImage imageNamed:@"logo.png"]];
    }else if(toInterfaceOrientation == UIInterfaceOrientationLandscapeLeft || toInterfaceOrientation == UIInterfaceOrientationLandscapeRight){
        [imgLogo setImage:[UIImage imageNamed:@"logo_landscape.png"]];
    }
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return YES;
}

- (void)dealloc {
    [magazineList release];
    [webView release];
    [imgView release];
    [pscrollView release];
    [activityIndicator release];
    [AdsList release];
    [tblList release];
    [imgLogo release];
    [super dealloc];
}
@end
