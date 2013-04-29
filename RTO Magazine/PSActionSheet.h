//
//  PLActionSheet.h
//
//  Based on PLActionSheet by Landon Fuller on 7/3/09.
//  Modified by Peter Steinberger
//

#import <UIKit/UIKit.h>

// A simple block-enabled API wrapper on top of UIActionSheet
@interface PSActionSheet : NSObject <UIActionSheetDelegate> {
    NSMutableArray *blocks_;
}

@property (nonatomic, strong, readonly) UIActionSheet *sheet;

+ (id)sheetWithTitle:(NSString *)title;

- (id)initWithTitle:(NSString *)title;

- (void)setCancelButtonWithTitle:(NSString *) title block:(void (^)()) block;
- (void)setDestructiveButtonWithTitle:(NSString *) title block:(void (^)()) block;
- (void)addButtonWithTitle:(NSString *) title block:(void (^)()) block;

- (void)showInView:(UIView *)view;
- (void)showFromBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated;
- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated;

- (NSUInteger)buttonCount;

@end
