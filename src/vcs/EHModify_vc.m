#import "EHModify_vc.h"

#import "ELHASO.h"


@interface EHModify_vc ()

- (IBAction)did_touch_cancel_button:(id)sender;

@end

@implementation EHModify_vc

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    // Implement this method to handle any initialization after your window
    // controller's window has been loaded from its nib file.
}

- (IBAction)did_touch_cancel_button:(id)sender
{
    DLOG(@"Aborting?");
    [[NSApplication sharedApplication] abortModal];
}

- (IBAction)did_touch_accept_button:(id)sender
{
    DLOG(@"Accepting");
    [[NSApplication sharedApplication] stopModal];
}

@end
