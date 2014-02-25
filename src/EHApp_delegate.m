#import "EHApp_delegate.h"

#import "EHRoot_vc.h"
#import "categories/NSString+seohyun.h"
#import "user_config.h"

#import "ELHASO.h"


NSString *decimal_separator_changed = @"decimal_separator_changed";
NSString *did_accept_file = @"NSNotificationDidAcceptFile";
NSString *did_accept_file_path = @"NSNotificationDidAcceptFilePath";
NSString *did_add_row = @"NSNotificationDidAddRow";
NSString *did_add_row_pos = @"NSNotificationDidAddRowPos";
NSString *did_change_changelog_version = @"NSNotificationDidChangeLogVersion";
NSString *did_import_csv = @"NSNotificationDidImportCSV";
NSString *did_remove_row = @"NSNotificationDidRemoveRow";
NSString *did_select_sync_tab = @"NSNotificationDidSelectSyncTab";
NSString *did_update_last_row = @"NSNotificationDidUpdateLastRow";
NSString *user_metric_prefereces_changed = @"user_metric_preferences_changed";


@interface EHApp_delegate ()

/// Keeps a strong reference to the history vc.
@property (nonatomic, strong) EHRoot_vc *history_vc;

@end

@implementation EHApp_delegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSString *db_path = get_path(@"", DIR_LIB);
    DLOG(@"Setting database path to %@", db_path);

    [self generate_changelog_timestamp_if_empty:db_path];

    if (!open_db([db_path cstring]))
        abort();
    DLOG(@"Got %lld entries", get_num_weights());

    // Obtain metric setting from environment.
    // http://stackoverflow.com/a/9997513/172690
    NSLocale *locale = [NSLocale autoupdatingCurrentLocale];
    const BOOL uses_metric = [[locale objectForKey:NSLocaleUsesMetricSystem]
        boolValue];
    NSString *separator = [locale objectForKey:NSLocaleDecimalSeparator];

    DLOG(@"Uses metric? %d, decimal separator is '%@'", uses_metric, separator);
    set_decimal_separator([separator cstring]);
    set_nimrod_metric_use_based_on_user_preferences();

    // Insert code here to initialize your application
    self.history_vc = [[EHRoot_vc alloc]
        initWithNibName:@"EHHistory_vc" bundle:nil];

    [self.window.contentView addSubview:self.history_vc.view];
    self.history_vc.view.frame = ((NSView*)self.window.contentView).bounds;
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

@end

#pragma mark -
#pragma mark Global functions

/// Helper method to update nimrod's global metric defaults.
void set_nimrod_metric_use_based_on_user_preferences(void)
{
    //const int pref = user_metric_preference();
    const int pref = 0;
    if (pref > 0)
        specify_metric_use((1 == pref));
    else
        specify_metric_use(system_uses_metric());
}

/** Wraps format_nsdate with a TWeight* accessor.
 *
 * Returns the empty string if something went wrong.
 */
NSString *format_date(TWeight *weight)
{
    if (!weight) return @"";
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:date(weight)];
    return format_nsdate(d);
}

/** Formats a date to text format.
 *
 * Returns the empty string if something went wrong.
 */
NSString *format_nsdate(NSDate *date)
{
    if (!date) return @"";

    static NSDateFormatter *formatter = nil;
    if (!formatter) {
        formatter = [NSDateFormatter new];
        [formatter setTimeStyle:NSDateFormatterMediumStyle];
        [formatter setDateStyle:NSDateFormatterMediumStyle];
    }
    if (!formatter) return @"";
    return [formatter stringFromDate:date];
}