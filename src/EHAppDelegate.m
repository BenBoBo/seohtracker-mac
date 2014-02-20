#import "EHAppDelegate.h"

#import "n_global.h"

@implementation EHAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    if (!open_db("/tmp"))
        abort();
    NSLog(@"Got %lld entries", get_num_weights());
}

@end
