#import "EHSettings_vc.h"

#import "EHApp_delegate.h"

#import "ELHASO.h"
#import "NSNotificationCenter+ELHASO.h"
#import "SHNotifications.h"
#import "n_global.h"
#import "user_config.h"


@interface EHSettings_vc ()

/// Label to update with the current setting.
@property (weak) IBOutlet NSTextField *weight_textfield;
/// Matrix of options the user can select.
@property (weak) IBOutlet NSMatrix *weight_matrix;

- (IBAction)did_touch_weight_matrix:(id)sender;

@end

@implementation EHSettings_vc

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

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center refresh_observer:self selector:@selector(refresh_ui_observer:)
        name:user_metric_prefereces_changed object:nil];
}

- (void)dealloc
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self
        name:user_metric_prefereces_changed object:nil];
}

#pragma mark -
#pragma mark Methods

/// Updates the dynamic widgets.
- (void)refresh_ui
{
    self.weight_textfield.stringValue = [NSString
        stringWithFormat:@"Weight unit: %s", get_weight_string()];

    const int user_pref = user_metric_preference();
    [self.weight_matrix selectCellAtRow:user_pref column:0];
}

/// Simple wrapper to refresh the UI when changes are done to user settings.
- (void)refresh_ui_observer:(NSNotification*)notification
{
    [self refresh_ui];
}

/// Changes the user preferences.
- (IBAction)did_touch_weight_matrix:(id)sender
{
    set_user_metric_preference((int)[self.weight_matrix selectedRow]);
    // An implicit call to refresh_ui is done through a global notification.
}

#pragma mark -
#pragma mark - RHPreferencesViewControllerProtocol

-(NSString*)identifier
{
    return NSStringFromClass(self.class);
}

-(NSImage*)toolbarItemImage
{
    return [NSImage imageNamed:NSImageNameActionTemplate];
}

-(NSString*)toolbarItemLabel
{
    return @"Settings";
}

-(NSView*)initialKeyView
{
    return nil;
}

- (void)viewWillAppear
{
    DLOG(@"EHSettings_vc viewWillAppear");
    [self refresh_ui];
}

@end
