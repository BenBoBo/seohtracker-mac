#import "EHPref_tracking_vc.h"

#import "EHApp_delegate.h"
#import "help_defines.h"

#import "ELHASO.h"
#import "NSNotificationCenter+ELHASO.h"
#import "SHNotifications.h"
#import "categories/NSObject+seohyun.h"
#import "n_global.h"
#import "user_config.h"


@interface EHPref_tracking_vc ()

/// Matrix of options the user can select.
@property (weak, nonatomic) IBOutlet NSMatrix *weight_matrix;

- (IBAction)did_touch_weight_matrix:(id)sender;
- (IBAction)did_touch_policy_button:(id)sender;

@end

@implementation EHPref_tracking_vc

#pragma mark -
#pragma mark - Life

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)awakeFromNib
{
    [self refresh_ui];
}

#pragma mark -
#pragma mark Methods

/// Updates the dynamic widgets.
- (void)refresh_ui
{
    [self.weight_matrix
        selectCellAtRow:(analytics_tracking_preference() ? 0 : 1) column:0];
}

/// Changes the user preferences.
- (IBAction)did_touch_weight_matrix:(id)sender
{
    set_analytics_tracking_preference(
        (0 == [self.weight_matrix selectedRow] ? true : false));
    [self refresh_ui];
}

/// Open the help to show the user the data collection info.
- (IBAction)did_touch_policy_button:(id)sender
{
    NSString *locBookName = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
    [[NSHelpManager sharedHelpManager]
     openHelpAnchor:help_anchor_tracking inBook:locBookName];
}

#pragma mark -
#pragma mark - RHPreferencesViewControllerProtocol

- (NSString*)identifier
{
    return [self class_string];
}

- (NSImage*)toolbarItemImage
{
    return [NSImage imageNamed:@"track_radar"];
}

- (NSString*)toolbarItemLabel
{
    return @"Tracking";
}

- (NSView*)initialKeyView
{
    return nil;
}

- (void)viewWillAppear
{
    [self refresh_ui];
}

@end
