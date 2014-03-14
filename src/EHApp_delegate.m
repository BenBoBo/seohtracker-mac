#import "EHApp_delegate.h"

#import "EHRoot_vc.h"
#import "EHSettings_vc.h"
#import "google_analytics_config.h"
#import "help_defines.h"

#import "AnalyticsHelper.h"
#import "ELHASO.h"
#import "RHPreferences.h"
#import "categories/NSString+seohyun.h"
#import "n_global.h"
#import "user_config.h"
#import "user_config.h"


@interface EHApp_delegate ()
    <NSApplicationDelegate>

/// Keeps a strong reference to the root vc.
@property (nonatomic, strong) EHRoot_vc *root_vc;
/// Caches the preferences window for lazy generation.
@property (nonatomic, strong) RHPreferencesWindowController *preferences_vc;

@end

@implementation EHApp_delegate

#pragma mark -
#pragma mark Life

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self start_google_analytics];

    NSString *db_path = get_path(@"", DIR_LIB);
    DLOG(@"Setting database path to %@", db_path);

    [self generate_changelog_timestamp_if_empty:db_path];

    if (!open_db([db_path cstring]))
        abort();
    DLOG(@"Got %lld entries", get_num_weights());

    configure_metric_locale();

    // Insert code here to initialize your application
    self.root_vc = [[EHRoot_vc alloc]
        initWithNibName:NSStringFromClass([EHRoot_vc class]) bundle:nil];
    self.window.delegate = self;

    [self.window.contentView addSubview:self.root_vc.view];
    self.root_vc.view.frame = ((NSView*)self.window.contentView).bounds;

    [self.window registerForDraggedTypes:@[NSURLPboardType]];
    [[NSApplication sharedApplication] setDelegate:self];

    dispatch_async_low(^{ [self build_preferences]; });
}

/// Quit app if the user closes the main window, which is the last.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
    return YES;
}

/// Extra prod to close the app if the user quits the main window.
- (void)windowWillClose:(NSNotification *)notification
{
    [[NSApplication sharedApplication] terminate:nil];
}

/// Tell google that the app is being closed.
- (void)applicationWillTerminate:(NSNotification *)notification
{
    [AnalyticsHelper.sharedInstance handleApplicationWillClose];
    [NSUserDefaults.standardUserDefaults synchronize];
}

#pragma mark -
#pragma mark Methods

/** Generates user preferences timestamp for changelog version.
 *
 * If the user doesn't have yet a version value for seen changelog file, this
 * function creates it based on the current bundle version, so as to not nag
 * new users with changes they likely are not interested in.
 */
- (void)generate_changelog_timestamp_if_empty:(NSString*)db_path
{
    if (config_changelog_version() > 0)
        return;

    DLOG(@"DB doesn't exist, setting changelog version to %0.1f",
        bundle_version());
    set_config_changelog_version(bundle_version());
}

/** If needed, rebuilds the preferences vc.
 *
 * Since building the preferences is slow, you can invoke this in a background
 * thread during initialisation. Hopefully it does not crash, or something
 * worse.
 */
- (void)build_preferences
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
            EHSettings_vc *pane1 = [[EHSettings_vc alloc]
                initWithNibName:NSStringFromClass([EHSettings_vc class])
                bundle:nil];

            self.preferences_vc = [[RHPreferencesWindowController alloc]
                initWithViewControllers:@[pane1] andTitle:@"Preferences"];
        });
}

/// Displayes the preferences window.
- (IBAction)show_preferences:(id)sender
{
    [self build_preferences];
    [self.preferences_vc showWindow:self];
}

/// Linked from the help menu, shows directly the appstore changes file.
- (IBAction)show_whats_new:(id)sender
{
    NSString *locBookName = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
    [[NSHelpManager sharedHelpManager]
        openHelpAnchor:help_anchor_appstore_changes inBook:locBookName];
}

/// Linked from the help menu, shows the license index page.
- (IBAction)show_licenses:(id)sender
{
    NSString *locBookName = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
    [[NSHelpManager sharedHelpManager]
     openHelpAnchor:help_anchor_licenses inBook:locBookName];
}

/// Linked from the main menu, starts the importation process.
- (IBAction)import_csv:(id)sender
{
    [self.root_vc import_csv];
}

/// Linked from the main menu, starts the exportation process.
- (IBAction)export_csv:(id)sender
{
    [self.root_vc export_csv];
}

/** Extracts bundle info to start google analytics.
 *
 * This uses the GOOGLE_ANALYTICS define which is not included in the source
 * repository.
 */
- (void)start_google_analytics
{
#ifdef GOOGLE_ANALYTICS
    NSBundle *b = [NSBundle mainBundle];
    NSString *name = [b objectForInfoDictionaryKey:@"CFBundleName"];
    NSString *version = [b objectForInfoDictionaryKey:@"CFBundleVersion"];

    AnalyticsHelper *analyticsHelper = [AnalyticsHelper sharedInstance];
    [analyticsHelper beginPeriodicReportingWithAccount:GOOGLE_ANALYTICS
        name:name version:version];
    DLOG(@"Registering with Google Analytics %@ name:%@ ver:%@",
        GOOGLE_ANALYTICS, name, version);
#else
    DLOG(@"Not activating Google Analytics, missing configuration.");
#ifdef APPSTORE
#error Can't build appstore release without google defines!
#endif
#endif
}

#pragma mark -
#pragma mark NSApplicationDelegate protocol

/** Hook to react to multiple files dropped on the icon.
 *
 * We simply pick the first with a csv file extension.
 */
- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    for (NSString *file in filenames) {
        NSString *ext = [[file pathExtension] lowercaseString];
        if ([ext isEqualToString:@"csv"]) {
            [NSApp abortModal];
            // Run the importation in the next runloop, so that abortModal has
            // a chance to notify/close modal sheets/windows.
            [self.root_vc performSelector:@selector(import_csv_file:)
                withObject:[NSURL fileURLWithPath:file] afterDelay:0];
            return;
        }
    }
}

#pragma mark -
#pragma mark NSDraggingDestination protocol

// Accepts the drag operation if it is a csv file being dragged in.
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];

    if (![[pboard types] containsObject:NSURLPboardType])
        return NSDragOperationNone;

    NSURL *file_url = [NSURL URLFromPasteboard:pboard];
    NSString *ext = [[file_url pathExtension] lowercaseString];
    if (![ext isEqualToString:@"csv"])
        return NSDragOperationNone;

    return NSDragOperationCopy;
}

/// Handles the drag operation, calls the importation method.
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    if (![[pboard types] containsObject:NSURLPboardType])
        return NO;

    NSURL *file_url = [NSURL URLFromPasteboard:pboard];
    NSString *ext = [[file_url pathExtension] lowercaseString];
    if (![ext isEqualToString:@"csv"])
        return NO;

    [self.root_vc performSelector:@selector(import_csv_file:)
        withObject:file_url afterDelay:0];

    return YES;
}

@end
