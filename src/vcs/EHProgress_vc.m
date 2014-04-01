#import "EHProgress_vc.h"

#import "ELHASO.h"
#import "categories/NSObject+seohyun.h"


@interface EHProgress_vc ()

/// Link to the progress indicator to start animating it.
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progress_indicator;

/// Maintains the chain to the parent to autodismiss ourselves.
@property (nonatomic, assign) NSWindowController *parent_vc;

@end

@implementation EHProgress_vc

#pragma mark -
#pragma mark Life

- (void)windowDidLoad
{
    [super windowDidLoad];
    [self.progress_indicator startAnimation:self];
}

#pragma mark -
#pragma mark Methods

/** Opens a progress indicator in the specified parent vc.
 *
 * After calling this the interface will be locked by the sheet, and you can do
 * your stuff to finally dismiss it.
 */
+ (EHProgress_vc*)start_in:(NSViewController*)parent_vc
{
    EHProgress_vc *ret = [[EHProgress_vc alloc]
        initWithWindowNibName:[EHProgress_vc class_string]];
    NSWindow *sheet = ret.window;

    [NSApp beginSheet:sheet modalForWindow:[parent_vc.view window]
        modalDelegate:nil didEndSelector:NULL contextInfo:NULL];

    [sheet makeKeyAndOrderFront:parent_vc];
    return ret;
}

/// Call when you have finished processing.
- (void)dismiss
{
    [NSApp endSheet:self.window];
    [self.window orderOut:self.parent_vc];
}

@end
