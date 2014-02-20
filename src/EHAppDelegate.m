#import "EHAppDelegate.h"

#import "categories/NSString+seohyun.h"
#import "n_global.h"

#import "ELHASO.h"

@implementation EHAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSString *db_path = get_path(@"", DIR_LIB);
    DLOG(@"Setting database path to %@", db_path);

    if (!open_db([db_path cstring]))
        abort();
    DLOG(@"Got %lld entries", get_num_weights());
}

@end
