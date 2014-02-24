#import "EHAppDelegate.h"

#import "EHHistory_vc.h"
#import "categories/NSString+seohyun.h"
#import "n_global.h"

#import "ELHASO.h"

@interface EHAppDelegate ()

/// Keeps a strong reference to the history vc.
@property (nonatomic, strong) EHHistory_vc *history_vc;

@end

@implementation EHAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSString *db_path = get_path(@"", DIR_LIB);
    DLOG(@"Setting database path to %@", db_path);

    if (!open_db([db_path cstring]))
        abort();
    DLOG(@"Got %lld entries", get_num_weights());

    // Insert code here to initialize your application
    self.history_vc = [[EHHistory_vc alloc]
        initWithNibName:@"EHHistory_vc" bundle:nil];

    [self.window.contentView addSubview:self.history_vc.view];
    self.history_vc.view.frame = ((NSView*)self.window.contentView).bounds;
}

@end
