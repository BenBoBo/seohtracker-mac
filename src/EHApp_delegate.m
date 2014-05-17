#import "EHApp_delegate.h"

#import "EHPref_tracking_vc.h"
#import "EHPref_units_vc.h"
#import "EHRoot_vc.h"
#import "appstore_changes.h"
#import "google_analytics_config.h"
#import "help_defines.h"

#import "AnalyticsHelper.h"
#import "ELHASO.h"
#import "NSNotificationCenter+ELHASO.h"
#import "RHPreferences.h"
#import "SHNotifications.h"
#import "categories/NSObject+seohyun.h"
#import "categories/NSString+seohyun.h"
#import "n_global.h"
#import "user_config.h"


NSString *midnight_happened = @"NSNotificationMidnightHappened";


@interface EHApp_delegate ()
    <NSApplicationDelegate, NSUserNotificationCenterDelegate>

/// Keeps a strong reference to the root vc.
@property (nonatomic, strong) EHRoot_vc *root_vc;
/// Caches the preferences window for lazy generation.
@property (nonatomic, strong) RHPreferencesWindowController *preferences_vc;

/// Menu entries which we bind at runtime.
@property (nonatomic, weak) IBOutlet NSMenuItem *delete_weight_menu;
@property (nonatomic, weak) IBOutlet NSMenuItem *modify_weight_menu;
@property (nonatomic, weak) IBOutlet NSMenuItem *add_weight_menu;
@property (nonatomic, weak) IBOutlet NSMenuItem *delete_all_weights_menu;

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

    [[NSNotificationCenter defaultCenter] refresh_observer:self
        selector:@selector(locale_did_change:)
        name:NSCurrentLocaleDidChangeNotification object:nil];

    self.root_vc = [[EHRoot_vc alloc]
        initWithNibName:[EHRoot_vc class_string] bundle:nil];
    self.window.delegate = self;

    [self.window.contentView addSubview:self.root_vc.view];
    self.root_vc.view.frame = ((NSView*)self.window.contentView).bounds;

    [self.window registerForDraggedTypes:@[NSURLPboardType]];
    [[NSApplication sharedApplication] setDelegate:self];

    // Register ourselves for user notifications. Just to open the changes log.
    NSUserNotificationCenter *user_notification_center =
        [NSUserNotificationCenter defaultUserNotificationCenter];
    user_notification_center.delegate = self;

    [self hook_menu_items];

    dispatch_async_low(^{ [self build_preferences]; });

    dispatch_async_low(^{ [self generate_changelog_notification]; });

    [self prepare_midnight_notification];

    // Detect if we are being launched due to the user clicking on notification.
    NSDictionary *start_info = aNotification.userInfo;
    NSUserNotification *user_notification = [start_info
        objectForKey: NSApplicationLaunchUserNotificationKey];
    if (user_notification) {
        // Emulate being clicked at runtime.
        [self userNotificationCenter:user_notification_center
            didActivateNotification:user_notification];
    }
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

/** Hook to learn when the user locale changes, so we can detect our stuff.
 *
 * If the user metric were on automatic, the notification
 * user_metric_prefereces_changed is generated for any visible EHSettings_vc to
 * update its view as if the user had changed the setting.
 *
 * This also checks if the locale decimal separator changed, generating the
 * event decimal_separator_changed if needed.
 */
- (void)locale_did_change:(NSNotification*)notification
{
    if (0 == user_metric_preference()) {
        DLOG(@"Weight automatic: rechecking system value");
        set_nimrod_metric_use_based_on_user_preferences();
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center postNotificationName:user_metric_prefereces_changed object:nil];
    }

    NSLocale *locale = [NSLocale autoupdatingCurrentLocale];
    NSString *separator = [locale objectForKey:NSLocaleDecimalSeparator];
    if (set_decimal_separator([separator cstring])) {
        DLOG(@"The decimal separator changed to '%@'", separator);
        [SHNotifications post_decimal_separator_changed];
    }
}

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
            EHPref_units_vc *pane1 = [[EHPref_units_vc alloc]
                initWithNibName:[EHPref_units_vc class_string] bundle:nil];

            EHPref_tracking_vc *pane2 = [[EHPref_tracking_vc alloc]
                initWithNibName:[EHPref_tracking_vc class_string] bundle:nil];

            self.preferences_vc = [[RHPreferencesWindowController alloc]
                initWithViewControllers:@[pane1, pane2] andTitle:@"Settings"];
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
    if (!analytics_tracking_preference()) {
        DLOG(@"Analytics disabled by user preference");
        return;
    }
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

/** Invoked during startup, checks changelog versions to show a notification.
 *
 * If the current runtime version is newer than the last stored preferences
 * version then a notification is added to the user notification center. The
 * user can touch the notification and this will display the changes log. Or he
 * can dismiss the notification.
 */
- (void)generate_changelog_notification
{
    const int dif =
        ceilf(EMBEDDED_CHANGELOG_VERSION - config_changelog_version());
    if (dif <= 0.01)
        return;

    NSUserNotification *n = [NSUserNotification new];
    n.title = @"Seohtracker was updated";
    n.subtitle = [NSString stringWithFormat:@"You have now version %@.",
        EMBEDDED_CHANGELOG_VERSION_STR];
    n.informativeText = @"Click to see what did change.";

    NSUserNotificationCenter *user_notification_center =
        [NSUserNotificationCenter defaultUserNotificationCenter];
    [user_notification_center deliverNotification:n];
    // Mark current version as seen.
    set_config_changelog_version(EMBEDDED_CHANGELOG_VERSION);
}

/** Sets the target/action for menu items.
 *
 * Since we create the view controller manually, we have to bind the menu items
 * too manually. Go back it time and tell myself to not use that tutorial and
 * instead create the GUI fully from interface builder.
 */
- (void)hook_menu_items
{
    for (NSMenuItem *menu in @[self.delete_weight_menu,
            self.modify_weight_menu, self.add_weight_menu,
            self.delete_all_weights_menu]) {
        menu.target = self.root_vc;
    }
    self.delete_weight_menu.action = @selector(did_touch_minus_button:);
    self.modify_weight_menu.action = @selector(did_touch_modify_button:);
    self.add_weight_menu.action = @selector(did_touch_plus_button:);
    self.delete_all_weights_menu.action = @selector(delete_all_entries:);
}

/** Schedules an event to fire at midnight.
 * The event will then generate a fake
 * UIApplicationSignificantTimeChangeNotification named midnight_happened and
 * reschedule itself for the next midnight event.
 */
- (void)prepare_midnight_notification
{
    // Find out the moment of the next midnight.
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *date_components = [calendar
        components:(NSYearCalendarUnit | NSMonthCalendarUnit |
            NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit |
            NSSecondCalendarUnit) fromDate:[NSDate date]];

    date_components.day += 1;
    date_components.hour = 0;
    date_components.minute = 0;
    date_components.second = 1;
    NSDate *future = [calendar dateFromComponents:date_components];
    const NSTimeInterval seconds = [future timeIntervalSinceNow];
    LASSERT(seconds > 0 && seconds <= 60 * 60 * 24, @"Unexpected future!");
    DLOG(@"Midnight happens at %@ in %0.1f seconds", future, seconds);

    [self performSelector:@selector(free_gremlins) withObject:nil
        afterDelay:seconds];
}

/** Generates midnight notification.
 *
 * Don't run this method directly! It's a callback for
 * prepare_midnight_notification. The midnight_happened notification will be
 * posted and prepare_midnight_notification called to loop again.
 */
- (void)free_gremlins
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:midnight_happened object:nil];
    [self prepare_midnight_notification];
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

#pragma mark -
#pragma mark NSUserNotificationCenterDelegate protocol

/** When the user clicks a notification, open the changes log.
 *
 * Also removes all previous notifications, since clicking any is enough and we
 * aren't using user notifications for anything else at the moment.
 */
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
    didActivateNotification:(NSUserNotification *)notification
{
    [self show_whats_new:center];
    [center removeAllDeliveredNotifications];
}

@end
