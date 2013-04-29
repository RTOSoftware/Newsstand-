//
//  PSPDFSearchViewController.m
//  PSPDFKit
//
//  Copyright 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFKit.h"
#import "PSPDFSearchViewController.h"
#import "PSPDFSearchResult.h"
#import "PSPDFViewController.h"
#import "NSMutableAttributedString+PSPDFKitAdditions.h"
#import "PSPDFHighlightAnnotationView.h"
#import "Selection.h"
#import "PSPDFSearchHighlightView.h"
#import "PSPDFSearchStatusCell.h"
#import "PSPDFDocumentSearcher.h"
#import <CoreText/CoreText.h>

@interface PSPDFSearchViewController() {
    NSMutableArray *searchResults_;
}

@property(nonatomic, strong) PSPDFDocument *document;
@property(nonatomic, strong) NSArray *searchResults;
@property(nonatomic, strong) UISearchBar *searchBar;
@property(nonatomic, ps_weak) PSPDFViewController *pdfController;
@property(nonatomic, assign) PSPDFSearchStatus searchStatus;
@end

@implementation PSPDFSearchViewController

@synthesize document = document_;
@synthesize searchResults = searchResults_;
@synthesize showCancel = showCancel_;
@synthesize searchBar = searchBar_;
@synthesize pdfController = pdfController_;
@synthesize searchStatus = searchStatus_;
@synthesize searchClassName = searchClassName_;
@synthesize popoverController = popoverController_;
@synthesize clearHighlightsWhenClosed = clearHighlightsWhenClosed_;

// ugly static variable - but our controller get destroyed after viewing
static NSString *lastSearchString_;
static NSString *lastDocumentUid_;

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// only used on iPad
- (void)setLargeContentSize:(BOOL)large {
    self.contentSizeForViewInPopover = large ? CGSizeMake(300, 2000) : CGSizeMake(300, 44);
}

- (void)setSearchStatus:(PSPDFSearchStatus)searchStatus updateTable:(BOOL)updateTable {
    if (searchStatus != searchStatus_) {
        PSPDFSearchStatus oldStatus = searchStatus_;
        [self willChangeValueForKey:@"searchStatus"];
        searchStatus_ = searchStatus;
        [self didChangeValueForKey:@"searchStatus"];
        
        if (updateTable) {
            [self.tableView beginUpdates];
            if (searchStatus != PSPDFSearchIdle) {
                if (oldStatus == PSPDFSearchIdle) {
                    [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:[searchResults_ count] inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
                }else {
                    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:[searchResults_ count] inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
                }
            }else {
                [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:[searchResults_ count] inSection:0]] withRowAnimation:UITableViewRowAnimationFade];            
            }
            [self.tableView endUpdates];   
        }
    }
}

- (void)setSearchStatus:(PSPDFSearchStatus)searchStatus {
    [self setSearchStatus:searchStatus updateTable:NO];
}

- (void)filterContentForSearchText:(NSString *)searchText scope:(NSString *)scope {
    // clear search
    self.searchResults = nil; // First clear the filtered array.
    [self.tableView reloadData];
    
    // start searching the html documents	
    if ([searchText length] >= kPSPDFSearchMinimumLength) {
        // TODO: add method to controller
        NSArray *visiblePageNumbers = [pdfController_ visiblePageNumbers];
        [self.document.documentSearcher searchForString:searchText visiblePages:visiblePageNumbers onlyVisible:NO];
        [self setLargeContentSize:YES];
    }else {
        [self setSearchStatus:PSPDFSearchIdle updateTable:YES];
        [self clearHighlightedSearchResults];
        [self setLargeContentSize:NO];
    }
}

- (void)updateResultCell:(UITableViewCell *)cell searchResult:(PSPDFSearchResult *)searchResult {
    PSPDFAttributedLabel *attributedLabel = (PSPDFAttributedLabel *)[cell viewWithTag:kPSPDFAttributedLabelTag];
    if (!attributedLabel) {
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.textLabel.textColor = [UIColor darkGrayColor];
        cell.detailTextLabel.text = @" "; // dummy content for cell to make space
        
        attributedLabel = [[PSPDFAttributedLabel alloc] init];
        attributedLabel.font = [UIFont systemFontOfSize:14];
        attributedLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        attributedLabel.tag = kPSPDFAttributedLabelTag;
        [cell.contentView addSubview:attributedLabel];
    }
    
    // setup regular cell
    NSString *searchString = self.searchBar.text;
    NSRange searchRange = [searchResult.previewText rangeOfString:searchString options:NSCaseInsensitiveSearch];    
    if([searchResult.previewText length]) {
        NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] initWithString:searchResult.previewText];
        [mas pspdfSetFont:[UIFont systemFontOfSize:14] range:NSMakeRange(0, [searchResult.previewText length])];    
        [mas pspdfSetFont:[UIFont boldSystemFontOfSize:14] range:searchRange];
        attributedLabel.text = mas;
    }else {
        // don't init with empty string!
        attributedLabel.text = [[NSMutableAttributedString alloc] initWithString:@""];
    }
    
    // do we have a page title here? only use outline if we have > 1 element (some documents just have page title, not what we want)
    NSString *outlineTitle = nil;
    if ([self.document.outlineParser.outline.children count] > 1) {
        outlineTitle = [self.document.outlineParser outlineElementForPage:searchResult.pageIndex exactPageOnly:NO].title;
        outlineTitle = [outlineTitle substringWithRange:NSMakeRange(0, MIN(25, [outlineTitle length]))]; // limit 
    }
    
    NSString *pageTitle = [NSString stringWithFormat:PSPDFLocalize(@"Page %d"), searchResult.pageIndex+1];
    NSString *cellText = outlineTitle ? [NSString stringWithFormat:@"%@, %@", outlineTitle, pageTitle] : pageTitle;
    cell.textLabel.text = cellText;
    cell.imageView.image = [[PSPDFCache sharedPSPDFCache] cachedImageForDocument:self.document page:searchResult.pageIndex size:PSPDFSizeTiny]; 
    
    // wait for imageView resizing (quite a hack, could be replaced with custom cell)
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect attributedFrame = CGRectMake(cell.textLabel.frame.origin.x, 20.f, cell.frame.size.width - cell.textLabel.frame.origin.x, 20.f);
        attributedLabel.frame = attributedFrame;
    });
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithDocument:(PSPDFDocument *)document pdfController:(PSPDFViewController *)pdfController {
    if ((self = [super init])) {
        PSPDFRegisterObject(self);
        searchClassName_ = [NSStringFromClass([PSPDFSearchStatusCell class]) copy];
        document_ = document;
        pdfController_ = pdfController; // weak
        [self setLargeContentSize:NO];
    }
    return self;
}

- (void)dealloc {
    // be sure search is canceled
    document_.documentSearcher.delegate = nil;
    [document_.documentSearcher cancelAllOperationsAndWait];
    PSPDFDeregisterObject(self);
    [[PSPDFCache sharedPSPDFCache] removeDelegate:self];
    pdfController_ = nil;
    searchBar_.delegate = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0.f, 0.f, self.view.frame.size.width, 0.f)];
    [self.searchBar sizeToFit];
    self.searchBar.tintColor = self.pdfController.tintColor;
    self.searchBar.showsCancelButton = showCancel_;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = PSPDFLocalize(@"Search");
    self.tableView.tableHeaderView = self.searchBar;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.document.documentSearcher.delegate = self;
    
    // initially, search is idlew
    self.searchStatus = PSPDFSearchIdle;
    
    // restore last search string if document is the same
    if (lastSearchString_ && (!lastDocumentUid_ || [lastDocumentUid_ isEqual:[document_ uid]])) {
        self.searchBar.text = lastSearchString_;
    }
    
    [self.searchBar becomeFirstResponder];
    [[PSPDFCache sharedPSPDFCache] addDelegate:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // manually call searchbar delegate if set in viewWillAppear
    if ([self.searchBar.text length]) {
        [self searchBar:self.searchBar textDidChange:self.searchBar.text];
    }
}

- (void)viewWillDisappear:(BOOL)animated {    
    [super viewWillDisappear:animated];
    
    self.document.documentSearcher.delegate = nil;
    
    // preserve last search string and document
    lastSearchString_ = [self.searchBar.text copy];
    lastDocumentUid_ = [[document_ uid] copy];
    
    [[PSPDFCache sharedPSPDFCache] removeDelegate:self];
    
    // instantly resign first responder, so we animate keyboard out while alpha animates popover
    [self.searchBar resignFirstResponder];
    
    if (clearHighlightsWhenClosed_) {
        [self clearHighlightedSearchResults];
    }
}

- (void)viewDidUnload {
    [super viewDidUnload];
    self.document.documentSearcher.delegate = nil;
    self.searchBar.delegate = nil;
    self.searchBar = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return PSIsIpad() ? YES : toInterfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (PSPDFSearchHighlightView *)highlightViewForSearchResult:(PSPDFSearchResult *)searchResult inView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[PSPDFSearchHighlightView class]]) {
            PSPDFSearchHighlightView *highlightView = (PSPDFSearchHighlightView *)subview;
            if ([highlightView.searchResult isEqual:searchResult]) {
                return highlightView;
            }
        }
    }
    return nil;
}

// private helper to iterate over PSPDFSearchHighlightView
- (void)iterateHighlightViewsWithBlock:(void(^)(PSPDFSearchHighlightView *highlightView))block {
    if (self.document.documentSearcher.searchMode == PSPDFSearchAdvancedWithHighlighting) {
        NSArray *visiblePageNumbers = [pdfController_ visiblePageNumbers];
        for (NSNumber *pageNumber in visiblePageNumbers) {
            PSPDFPageView *pageView = [pdfController_ pageViewForPage:[pageNumber integerValue]];
            for (UIView *subview in pageView.subviews) {
                if ([subview isKindOfClass:[PSPDFSearchHighlightView class]]) {
                    PSPDFSearchHighlightView *highlightView = (PSPDFSearchHighlightView *)subview;
                    block(highlightView);
                }
            }
        }
    }    
}    

- (void)animateSearchHighlight:(PSPDFSearchResult *)searchResult {
    [self iterateHighlightViewsWithBlock:^(PSPDFSearchHighlightView *highlightView) {
        if (highlightView.searchResult == searchResult) {
            [highlightView popupAnimation];
        }
    }];
}

- (void)clearHighlightedSearchResults {
    [self iterateHighlightViewsWithBlock:^(PSPDFSearchHighlightView *highlightView) {
        [highlightView removeFromSuperview];
    }];
}

// add to the current page!
- (void)addHighlightSearchResults:(NSArray *)searchResults {
    if (self.document.documentSearcher.searchMode == PSPDFSearchAdvancedWithHighlighting) {
        PSPDFPageView *pageView = nil;
        NSArray *visiblePageNumbers = [pdfController_ visiblePageNumbers];
        for (PSPDFSearchResult *searchResult in searchResults) {
            if (searchResult.selection) {
                NSUInteger page = searchResult.pageIndex;
                if ([visiblePageNumbers containsObject:[NSNumber numberWithInteger:page]]) {
                    if (!pageView || pageView.page != page) {
                        pageView = [pdfController_ pageViewForPage:page];
                    }
                    
                    // mark text
                    if (pageView) {
                        PSPDFSearchHighlightView *highlight = [self highlightViewForSearchResult:searchResult inView:pageView];
                        if (!highlight) {
                            highlight = [[PSPDFSearchHighlightView alloc] initWithSearchResult:searchResult];
                            [pageView insertSubview:highlight aboveSubview:pageView.pdfView]; // respect other views
                            [highlight popupAnimation];
                        }
                    }
                }
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFSearchDelegate

- (void)willStartSearchForString:(NSString *)searchString isFullSearch:(BOOL)isFullSearch {
    if (!isFullSearch) {
        return; // ignore partial search updates
    }
    
    PSPDFLog(@"Starting search for %@.", searchString);
    [self setSearchStatus:PSPDFSearchActive updateTable:YES];
    self.searchResults = [NSMutableArray array];
    [self.tableView reloadData];
    
    // clear view
    [self clearHighlightedSearchResults];    
}

- (void)didUpdateSearchForString:(NSString *)searchString newSearchResults:(NSArray *)searchResults forPage:(NSUInteger)page {
    PSPDFLog(@"Updated search status for %@, page %d, results:%@", searchString, page, searchResults);
    
    // ignore if filtered list content is not set (new search is already in progress?)
    if (!searchResults_ || ![searchString isEqualToString:self.searchBar.text]) {
        PSPDFLog(@"skipping search update...");
        return;
    }
    if ([searchResults count] > 0) {
        NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:[searchResults count]];
        for (PSPDFSearchResult *searchResult in searchResults) {
            // note: this may just be an *update* to include selection data.
            NSUInteger objectIndex = [searchResults_ indexOfObject:searchResult];
            if (objectIndex != NSNotFound) {
                if (searchResult.selection) {  // replace only if we have selectionData
                    [searchResults_ replaceObjectAtIndex:objectIndex withObject:searchResult];
                }
            }else {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[searchResults_ count] inSection:0];
                [indexPaths addObject:indexPath];
                [searchResults_ addObject:searchResult];
            }
        }
        if ([indexPaths count]) {
            [self.tableView beginUpdates];
            [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
            [self.tableView endUpdates];
        }
        
        [self addHighlightSearchResults:searchResults];
    }    
}

- (void)didFinishSearchForString:(NSString *)searchString searchResults:(NSArray *)searchResults isFullSearch:(BOOL)isFullSearch {
    PSPDFLog(@"Search for %@ finished.", searchString);
    if (!isFullSearch || ![searchString isEqualToString:self.searchBar.text]) {
        return; // ignore partial search updates
    }
    
    [self setSearchStatus:PSPDFSearchFinished updateTable:YES];
}

- (void)didCancelSearchForString:(NSString *)searchString isFullSearch:(BOOL)isFullSearch {
    if (!isFullSearch || ![searchString isEqualToString:self.searchBar.text]) {
        return; // ignore partial search updates
    }
    
    PSPDFLog(@"Search for %@ cancelled.", searchString);
    [self setSearchStatus:PSPDFSearchCancelled updateTable:YES];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= [self.searchResults count]) { // user pressed on search status cell
        return; 
    }
    PSPDFSearchResult *searchResult = [self.searchResults objectAtIndex:indexPath.row];
    
    if (searchResult.selection) {
        [self animateSearchHighlight:searchResult];
    }else {
        if (self.document.documentSearcher.searchMode == PSPDFSearchAdvancedWithHighlighting) {
            // if we don't have selection data, perform a new, limited search.
            // we have to manually find out what page set we're getting (which is pretty chumbersome)
            NSMutableArray *visiblePages = [NSMutableArray arrayWithObject:[NSNumber numberWithInteger:searchResult.pageIndex]];
            if([self.pdfController isDualPageMode]) {
                if ([self.pdfController isRightPageInDoublePageMode:searchResult.pageIndex] && searchResult.pageIndex > 0) {
                    [visiblePages addObject:[NSNumber numberWithInteger:searchResult.pageIndex-1]];
                }else if (searchResult.pageIndex+1 < [self.document pageCount]) {
                    [visiblePages addObject:[NSNumber numberWithInteger:searchResult.pageIndex+1]];
                }
            }
            [self.document.documentSearcher searchForString:self.searchBar.text visiblePages:visiblePages onlyVisible:YES];
        }
    }
    
    // hide controller
    if (PSIsIpad()) {
        [self.searchBar resignFirstResponder];
        [self.popoverController.delegate popoverControllerShouldDismissPopover:self.popoverController];
        [self.popoverController dismissPopoverAnimated:YES];
        [self.popoverController.delegate popoverControllerDidDismissPopover:self.popoverController];
    }else {
        [self dismissModalViewControllerAnimated:YES];
    }
    
    // TODO: timing problem. need proper scroll-delegate for pdfController.
    [pdfController_ scrollToPage:searchResult.pageIndex animated:NO];//PSPDFShouldAnimate()];
    pdfController_.viewMode = PSPDFViewModeDocument; // ensure that we show documents
    
    // add highlight results
    [self addHighlightSearchResults:searchResults_];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSUInteger listCount = [searchResults_ count];
    if (listCount || searchStatus_ != PSPDFSearchIdle) {
        listCount++; // add one entry for the status cell (activty/search ended)
    }
    
    return listCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *pageCellID = @"PSPDFSearchTableViewCell";
    static NSString *searchCellID = @"PSPDFSearchActivityTableCell";
    BOOL searchCell = (searchStatus_ != PSPDFSearchIdle) && indexPath.row == [searchResults_ count];
    NSString *cellID = searchCell ? searchCellID : pageCellID;
    UITableViewCell *cell = nil;
    
	// step 1: is there a reusable cell?
	cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    
	// step 2: no? -> create new cell
	if (cell == nil) {
        if (searchCell) {
            cell = [[NSClassFromString(searchClassName_) alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        }else {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        }
    }
    
    if(searchCell) {
        PSPDFSearchStatusCell *searchStatusCell = (PSPDFSearchStatusCell *)cell;
        [searchStatusCell updateCellWithSearchStatus:searchStatus_ results:[searchResults_ count]];
    }else {
        PSPDFSearchResult *searchResult = [searchResults_ objectAtIndex:indexPath.row];
        [self updateResultCell:cell searchResult:searchResult];
    }
    
    return cell;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterContentForSearchText:searchText scope:0];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *) searchBar {
    [self dismissModalViewControllerAnimated:YES]; // showCancel is set for modal view
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFCacheDelegate

- (void)didCachePageForDocument:(PSPDFDocument *)document page:(NSUInteger)page image:(UIImage *)cachedImage size:(PSPDFSize)size {
    for (PSPDFSearchResult *searchResult in searchResults_) {
        if (size == PSPDFSizeTiny && searchResult.document == document && searchResult.pageIndex == page) {
            NSUInteger searchIndex = [searchResults_ indexOfObject:searchResult];
            [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:searchIndex inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
            break;
        }
    }
}

@end
