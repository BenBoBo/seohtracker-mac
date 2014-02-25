#import "EHModify_vc.h"

#import "NSString+seohyun.h"

#import "ELHASO.h"


@interface EHModify_vc ()

/// Internal value keeping the date.
@property (nonatomic, strong) NSDate *date;
/// Internal value keeping the weight.
@property (nonatomic, assign) float weight;
/// Remembers if the caller is modifying an existing weight.
@property (nonatomic, assign) BOOL modification;

/// Used to notify the user that something is wrong.
@property (weak) IBOutlet NSTextField *warning_textfield;
/// Can display modification or creation
@property (weak) IBOutlet NSTextField *title_textfield;
/// Selects the day date graphically.
@property (weak) IBOutlet NSDatePicker *date_picker;
/// Allows changing the specific hour.
@property (weak) IBOutlet NSDatePicker *hour_picker;
/// Link to disallow accepting invalid values.
@property (weak) IBOutlet NSButton *accept_button;
/// Text field containing the weight.
@property (weak) IBOutlet NSTextField *weight_textfield;
/// Used to display the mass unit currently in use.
@property (weak) IBOutlet NSTextField *unit_textfield;

- (IBAction)did_touch_cancel_button:(id)sender;
- (IBAction)did_touch_accept_button:(id)sender;

@end

@implementation EHModify_vc

#pragma mark -
#pragma mark Life

- (id)initWithWindow:(NSWindow *)window
{
    if (!(self = [super initWithWindow:window]))
        return nil;

    self.date = [NSDate date];
    self.weight = get_localized_weight(0);
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    // TODO: Use NSNumberFormatter
    self.weight_textfield.stringValue = [NSString stringWithFormat:@"%0.1f",
        self.weight];
    self.date_picker.dateValue = self.date;
    self.hour_picker.dateValue = self.date;
    [self.warning_textfield setHidden:YES];

    self.title_textfield.stringValue = (self.modification ?
        @"Modifying previous value" : @"Enter values for new measurement");
    self.unit_textfield.stringValue = @(get_weight_string());
}

#pragma mark -
#pragma mark Methods

/** Sets the values for weight modification.
 *
 * Call this before displaying the sheet. Nil values don't change anything.
 */
- (void)set_values_from:(TWeight*)weight
{
    if (!weight)
        return;
    self.weight = get_localized_weight(weight);
    self.date = [NSDate dateWithTimeIntervalSince1970:date(weight)];
    self.modification = YES;
}

/** Returns the currenlty set date.
 *
 * This will reflect new values only if the user pressed the accept button.
 */
- (NSDate*)accepted_date
{
    return self.date;
}

/** Returns the currently set weight.
 *
 * This will reflect new values only if the user pressed the accept button.
 */
- (float)accepted_weight
{
    return self.weight;
}

/// Abort, don't touch the logical values.
- (IBAction)did_touch_cancel_button:(id)sender
{
    DLOG(@"Aborting?");
    [[NSApplication sharedApplication] abortModal];
}

/// Accept, change the logical values to good ones so they can be retrieved.
- (IBAction)did_touch_accept_button:(id)sender
{
    DLOG(@"Accepting");

    // Extract only part of the date values. See
    // http://stackoverflow.com/a/18708107/172690
    NSCalendar *calendar = [NSCalendar currentCalendar];

    // Split the date into components but only take the year, month and day and
    // leave the rest behind.
    NSDateComponents *date_components = [calendar
        components:(NSYearCalendarUnit | NSMonthCalendarUnit |
            NSDayCalendarUnit) fromDate:self.date_picker.dateValue];

    NSDateComponents *time_components = [calendar
        components:(NSHourCalendarUnit | NSMinuteCalendarUnit |
            NSSecondCalendarUnit) fromDate:self.hour_picker.dateValue];

    date_components.hour = time_components.hour;
    date_components.minute = time_components.minute;
    date_components.second = time_components.second;
    self.date = [calendar dateFromComponents:date_components];
    DLOG(@"Setting logical date to %@", self.date);

    [[NSApplication sharedApplication] stopModal];
}

#pragma mark -
#pragma mark NSControlTextEditingDelegate protocol

/** Validates the text field.
 *
 * The false returned here is respected for keyboard users, they can't tab away
 * from the field until it is correct. But they could still press the accept
 * button…
 */
- (BOOL)control:(NSControl *)control isValidObject:(id)object
{
    const BOOL ret = is_weight_input_valid([object cstring]);
    DLOG(@"Is valid? %d", ret);
    return ret;
}

/** Called after changes to float weight, validates it and changes the UI.
 *
 * If the text is invalid, a bad label will be displayed below the text field
 * and the accept button disabled. Otherwise everything is fine.
 */
- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSTextView *fieldEditor = [[aNotification userInfo]
        objectForKey:@"NSFieldEditor"];
    NSString *theString = [[fieldEditor textStorage] string];
    const BOOL valid = theString.length &&
        is_weight_input_valid([theString cstring]);
    self.accept_button.enabled = valid;
    [self.warning_textfield setHidden:valid];
}

@end
