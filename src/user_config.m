#import "user_config.h"

#import "EHApp_delegate.h"


#import "ELHASO.h"


static NSString *k_user_metric_preference = @"USER_METRIC_PREFERENCE";
static NSString *k_config_changelog_version = @"USER_CHANGELOG_VERSION";


/** Returns the current user setting changelog value.
 *
 * Returns a value greater than zero if the user setting exists, zero otherwise.
 */
float config_changelog_version(void)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d floatForKey:k_config_changelog_version];
}

/** Sets the float value for the changelog version preference.
 *
 * Values lower than zero are clamped to zero, which is interpreted as no
 * value. Also generates the notification did_change_changelog_version.
 */
void set_config_changelog_version(float value)
{
    if (value < 0) value = 0;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setFloat:value forKey:k_config_changelog_version];
    [d synchronize];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:did_change_changelog_version object:nil];
}

/** Returns the value of the embedded app version.
 *
 * Returns zero if something went wrong.
 */
float bundle_version(void)
{
    return [[[[NSBundle mainBundle] infoDictionary]
        objectForKey:@"CFBundleVersion"] floatValue];
}

/** Returns the user metric preference.
 *
 * This will be zero if the user hasn't set anything, therefore accepting the
 * automatic value. Otherwise it will be an integer mapping
 * (kilograms|pounds)+1.
 */
int user_metric_preference(void)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return (int)[d integerForKey:k_user_metric_preference];
}

/** Saves the specified value to the user preferences.
 *
 * See user_metric_preference() for valid values. Also generates the
 * notification user_metric_prefereces_changed.
 */
void set_user_metric_preference(int value)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:value forKey:k_user_metric_preference];
    [d synchronize];

    set_nimrod_metric_use_based_on_user_preferences();
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:user_metric_prefereces_changed object:nil];
}

/** Returns true if the system is set up to use the metric system.
 *
 * This function doesn't read any configuration data, it always returns the
 * current system locale.
 */
bool system_uses_metric(void)
{
    // Obtain metric setting from environment.
    // http://stackoverflow.com/a/9997513/172690
    NSLocale *locale = [NSLocale autoupdatingCurrentLocale];
    const BOOL uses_metric = [[locale objectForKey:NSLocaleUsesMetricSystem]
        boolValue];
    return uses_metric;
}