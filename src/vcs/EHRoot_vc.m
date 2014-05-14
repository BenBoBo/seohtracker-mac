#import "EHRoot_vc.h"

#import "EHApp_delegate.h"
#import "EHBannerButton.h"
#import "EHGraph_scroll.h"
#import "EHModify_vc.h"
#import "EHProgress_vc.h"

#import "ELHASO.h"
#import "NSBezierPath+Seohtracker.h"
#import "NSNotificationCenter+ELHASO.h"
#import "SHNotifications.h"
#import "categories/NSObject+seohyun.h"
#import "categories/NSString+seohyun.h"
#import "formatters.h"

#import <QuartzCore/QuartzCore.h>


@interface EHRoot_vc ()
    <EHGraph_click_delegate>

/// The table we need to refresh during scrolls.
@property (nonatomic, weak) IBOutlet NSTableView *table_view;
/// Hint displaying at the bottom of the table_view.
@property (nonatomic, weak) IBOutlet NSTextField *table_overlay;
/// Holds a read only text for the selected date.
@property (nonatomic, weak) IBOutlet NSTextField *read_date_textfield;
/// Holds a read only text for the selected weight.
@property (nonatomic, weak) IBOutlet NSTextField *read_weight_textfield;
/// Needed to hide the button when nothing is selected.
@property (nonatomic, weak) IBOutlet NSButton *modify_button;
/// Avoids refreshing the UI during multiple awakeFromNib calls.
@property (nonatomic, assign) BOOL did_awake;
/// Needs to be disabled if nothing is selected.
@property (weak) IBOutlet NSButton *minus_button;
/// Scrollview containing the graph.
@property (weak) IBOutlet EHGraph_scroll *graph_scroll;
/// Rotating local ads.
@property (weak) IBOutlet EHBannerButton *banner_button;
/// The image on top of the banner to produce the fading.
@property (nonatomic, strong) IBOutlet NSImageView *banner_overlay;

/// Keeps the name of the input file being imported.
@property (nonatomic, strong) NSString *csv_to_import;

/// Points to the current pseudo modal sheet.
@property (nonatomic, weak) NSWindow *modal_sheet_window;

@end

@implementation EHRoot_vc

#pragma mark -
#pragma mark Life

- (id)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    if (!self.did_awake) {
        DLOG(@"Awakening!");
        self.did_awake = YES;
        [self refresh_ui];
        const long last = get_num_weights();
        if (last > 0) [self.table_view scrollRowToVisible:last - 1];
        self.graph_scroll.click_delegate = self;
        self.graph_scroll.redraw_lock = get_last_weight();

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center refresh_observer:self selector:@selector(refresh_ui_observer:)
            name:user_metric_prefereces_changed object:nil];

        self.banner_button.overlay = self.banner_overlay;
        [self.banner_button start];
    }
}

- (void)dealloc
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self
        name:user_metric_prefereces_changed object:nil];
}

#pragma mark -
#pragma mark Methods

/// Returns the currently selected weight or nil.
- (TWeight*)selected_weight;
{
    const NSInteger pos = [self.table_view selectedRow];
    if (pos >= 0)
        return get_weight(pos);
    else
        return nil;
}

/// Refreshes the labels using the current state.
- (void)refresh_ui
{
    TWeight *w = [self selected_weight];
    if (w) {
        self.read_date_textfield.stringValue = [NSString
            stringWithFormat:@"Date: %@", format_relative_date(w)];
        self.read_weight_textfield.stringValue = [NSString
            stringWithFormat:@"Weight: %s %s",
            format_weight_with_current_unit(w), get_weight_string()];
        self.modify_button.enabled = YES;
        self.minus_button.enabled = YES;
    } else {
        self.read_date_textfield.stringValue = @"";
        self.read_weight_textfield.stringValue = @"";
        self.modify_button.enabled = NO;
        self.minus_button.enabled = NO;
    }
    [self.graph_scroll select_weight:w];

    const BOOL show_overlay = get_num_weights() < 5;
    [self.table_overlay setHidden:(show_overlay ? NO : YES)];
}

/// Simple wrapper to refresh the UI when changes are done to user settings.
- (void)refresh_ui_observer:(NSNotification*)notification
{
    const NSInteger pos = [self.table_view selectedRow];
    [self refresh_ui];
    [self.table_view reloadData];
    // Attempt to recover previous row selection.
    [self select_table_pos:pos];
    [self.graph_scroll refresh_graph];
    self.graph_scroll.redraw_lock = [self selected_weight];
}

/// Forces the table and scrolling to a specific row in the table.
- (void)select_table_pos:(const NSInteger)pos
{
    if (pos >= 0) {
        NSIndexSet *rows = [NSIndexSet indexSetWithIndex:pos];
        [self.table_view selectRowIndexes:rows byExtendingSelection:NO];
        [self.table_view scrollRowToVisible:pos];
    }
}

/// Called when the user wants to modify an existing value.
- (IBAction)did_touch_modify_button:(id)sender
{
    TWeight *weight = [self selected_weight];
    EHModify_vc *vc = [[EHModify_vc alloc]
        initWithWindowNibName:[EHModify_vc class_string]];
    [vc set_values_from:weight for_new_value:NO];

    const NSInteger ret = [self begin_modal_sheet:vc.window];
    [self end_modal_sheet];

    if (NSModalResponseAbort == ret) {
        DLOG(@"User aborted modification");
        return;
    }

    // Change the data values.
    DLOG(@"Accepting values! %@ %0.1f", vc.accepted_date, vc.accepted_weight);
    if (modify_weight_value(weight, vc.accepted_weight) < 0) {
        LOG(@"Error modifying weight value to %0.1f", vc.accepted_weight);
        [self.table_view reloadData];
        return;
    }

    long long old_pos, new_pos;
    modify_weight_date(weight, [vc.accepted_date timeIntervalSince1970],
        &old_pos, &new_pos);
    if (old_pos < 0 || new_pos < 0) {
        LOG(@"Error modifying weight date to %@", vc.accepted_date);
        [self.table_view reloadData];
        return;
    }

    // Refresh the rows.
    NSIndexSet *new_row = [NSIndexSet indexSetWithIndex:new_pos];
    [self.table_view beginUpdates];
    [self.table_view removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:old_pos]
        withAnimation:NSTableViewAnimationSlideLeft];
    [self.table_view insertRowsAtIndexes:new_row
        withAnimation:NSTableViewAnimationSlideRight];
    [self.table_view endUpdates];
    [self refresh_row_backgrounds];

    // Force selection to the new position.
    [self.table_view deselectAll:self];
    [self.table_view selectRowIndexes:new_row byExtendingSelection:NO];
    [self animate_scroll_to:new_pos];
    // Focus tableview.
    [[self.table_view window] makeFirstResponder:self.table_view];
    [self.graph_scroll refresh_graph];
    self.graph_scroll.redraw_lock = [self selected_weight];
}

/// Removes the selected weight, but first asks if really should be done.
- (IBAction)did_touch_minus_button:(id)sender
{
    TWeight *weight = [self selected_weight];
    RASSERT(weight, @"No weight selected? What should I remove?", return);

    [self.table_view scrollRowToVisible:[self.table_view selectedRow]];

    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSWarningAlertStyle;
    alert.showsHelp = NO;
    alert.messageText = @"Are you sure you want to remove the entry?";
    alert.informativeText = [NSString stringWithFormat:@"%s %s - %@",
        format_weight_with_current_unit(weight), get_weight_string(),
        format_relative_date(weight)];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Accept"];
    const BOOL accept = (NSAlertSecondButtonReturn == [alert runModal]);
    if (!accept)
        return;

    const long long pos = remove_weight(weight);
    if (pos < 0) {
        LOG(@"Error deleting selected weight");
        [self.table_view reloadData];
    } else {
        [self.table_view deselectAll:self];
        [self.table_view beginUpdates];
        [self.table_view removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:pos]
            withAnimation:NSTableViewAnimationSlideLeft];
        [self.table_view endUpdates];
        [self refresh_row_backgrounds];
    }
    [self.graph_scroll refresh_graph];
    self.graph_scroll.redraw_lock = [self selected_weight];
}

/// Adds a new entry, displaying the modification sheet.
- (IBAction)did_touch_plus_button:(id)sender
{
    EHModify_vc *vc = [[EHModify_vc alloc]
        initWithWindowNibName:[EHModify_vc class_string]];
    [vc set_values_from:get_last_weight() for_new_value:YES];

    const NSInteger ret = [self begin_modal_sheet:vc.window];
    [self end_modal_sheet];

    if (NSModalResponseAbort == ret) {
        DLOG(@"User aborted modification");
        return;
    }

    // Add the value.
    const long long initial_weight_pos = add_weight(vc.accepted_weight);
    TWeight *weight = get_weight(initial_weight_pos);
    if (!weight) {
        LOG(@"Error adding weight with %0.1f", vc.accepted_weight);
        return;
    }

    // Now we have to modify the date, which might reposition it too.
    long long old_pos, new_pos;
    modify_weight_date(weight, [vc.accepted_date timeIntervalSince1970],
        &old_pos, &new_pos);
    if (old_pos < 0 || new_pos < 0) {
        LOG(@"Error modifying weight date to %@", vc.accepted_date);
        [self.table_view reloadData];
        return;
    }

    // Refresh the rows.
    NSIndexSet *new_row = [NSIndexSet indexSetWithIndex:new_pos];
    [self.table_view beginUpdates];
    [self.table_view insertRowsAtIndexes:new_row
        withAnimation:NSTableViewAnimationSlideRight];
    [self.table_view endUpdates];
    [self refresh_row_backgrounds];

    // Force selection to the new position.
    [self.table_view deselectAll:self];
    [self.table_view selectRowIndexes:new_row byExtendingSelection:NO];
    [self animate_scroll_to:new_pos];
    // Focus tableview.
    [[self.table_view window] makeFirstResponder:self.table_view];
    [self.graph_scroll refresh_graph];
    self.graph_scroll.redraw_lock = [self selected_weight];
}

/** Better animated scrollRowToVisible.
 *
 * See http://stackoverflow.com/a/8480325/172690. While scrollRowToVisible
 * *works*, it works in that if the top pixel of the added row is visible no
 * more movement is done, or maybe the reason given at
 * http://stackoverflow.com/q/16313799/172690. In any case, this animates a
 * scroll, and works for insertions at the end of the table properly.
 */
- (void)animate_scroll_to:(NSInteger)pos
{
    NSRect rowRect = [self.table_view rectOfRow:pos];
    NSRect viewRect = [[self.table_view superview] frame];
    NSPoint scrollOrigin = rowRect.origin;
    scrollOrigin.y += (rowRect.size.height - viewRect.size.height) / 2;
    if (scrollOrigin.y < 0) scrollOrigin.y = 0;
    [[[self.table_view superview] animator] setBoundsOrigin:scrollOrigin];
}

/// Starts the importation by asking the user for a CSV file.
- (void)import_csv
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setShowsHiddenFiles:NO];
    [panel setTitle:@"Select a .csv file to import"];
    [panel setPrompt:@"Import"];
    [panel setAllowedFileTypes:@[@"csv"]];
    [panel setAllowsOtherFileTypes:NO];

    [panel beginSheetModalForWindow:[self.view window]
        completionHandler:^(NSInteger result) {

            if (NSFileHandlingPanelOKButton == result)
                [self import_csv_file:panel.URLs[0]];

            [panel orderOut:nil];
        }];
}

/** Callback when the user clicks OK on the open panel.
 *
 * Receives the filenames to be imported. Will be just one. The progress is
 * displayed in a sheet based on code from
 * http://stackoverflow.com/a/8144181/172690 while nimrod code processes the
 * stuff.
 */
- (void)import_csv_file:(NSURL*)url
{
    [self end_modal_sheet];
    self.csv_to_import = [url path];
    DLOG(@"Would be reading %@", self.csv_to_import);

    // First scan how many entries there are.
    self.table_view.enabled = NO;
    EHProgress_vc *progress = [EHProgress_vc start_in:self];

    const long long csv_entries =
        scan_csv_for_entries([self.csv_to_import cstring]);

    [progress dismiss];
    self.table_view.enabled = YES;

    // Ask the user what kind of importation is to be performed.
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSInformationalAlertStyle;
    alert.showsHelp = NO;
    alert.messageText = [NSString stringWithFormat:@"Found %lld records in %@. "
            @"Replace your current database or only add new entries not "
            @"yet present?", csv_entries, self.csv_to_import];
    [alert addButtonWithTitle:@"Cancel importation"];
    [alert addButtonWithTitle:@"Only add"];
    [alert addButtonWithTitle:@"Replace database"];

    const long selected_button = [alert runModal];
    if (selected_button == NSAlertFirstButtonReturn)
        return;

    // Cool, replace or add the entries.
    self.table_view.enabled = NO;
    progress = [EHProgress_vc start_in:self];

    const BOOL replace = (selected_button != NSAlertSecondButtonReturn);
    DLOG(@"Importing, replace set to %d", replace);
    const BOOL ret = import_csv_into_db([self.csv_to_import cstring], replace);
    DLOG(@"Importation reported %d, with replace as %d", ret, replace);

    [self.table_view reloadData];
    [self refresh_ui];
    [self.graph_scroll refresh_graph];

    [progress dismiss];
    self.table_view.enabled = YES;

    alert = [NSAlert new];
    alert.alertStyle = NSInformationalAlertStyle;
    alert.showsHelp = NO;
    alert.messageText = (ret ?
        @"Success importing file" : @"Could not import file!");
    [alert addButtonWithTitle:@"Close"];
    [alert runModal];
}

/// Starts the exportation by asking the user where to place the CSV file.
- (void)export_csv
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setShowsHiddenFiles:NO];
    [panel setTitle:@"Select where to export the .csv file"];
    [panel setPrompt:@"Export"];
    [panel setAllowedFileTypes:@[@"csv"]];
    [panel setAllowsOtherFileTypes:NO];
    [panel setNameFieldStringValue:@"Seohtracker export.csv"];
    [panel setNameFieldStringValue:[self generate_csv_export_filename]];

    [panel beginSheetModalForWindow:[self.view window]
        completionHandler:^(NSInteger result) {

            if (NSFileHandlingPanelOKButton == result)
                [self export_csv_file:[panel.URL path]];

            [panel orderOut:nil];
        }];
}

/** Callback when the user clicks OK on the save panel.
 *
 * Receives where should the file be exported to.
 */
- (void)export_csv_file:(NSString*)path
{
    DLOG(@"Would be saving to %@", path);

    self.table_view.enabled = NO;
    EHProgress_vc *progress = [EHProgress_vc start_in:self];

    const bool ret = export_database_to_csv([path cstring]);

    [progress dismiss];
    self.table_view.enabled = YES;

    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSInformationalAlertStyle;
    alert.showsHelp = NO;
    alert.messageText = (ret ?
        @"Success exporting file" : @"Could not export file!");
    [alert addButtonWithTitle:@"Close"];
    [alert runModal];
}

/// Returns a potential filename for csv exportation using the current date.
- (NSString*)generate_csv_export_filename
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSString *dateComponents = @"yyMMdd";
    [dateFormatter setDateFormat:[NSDateFormatter
        dateFormatFromTemplate:dateComponents
        options:0 locale:[NSLocale currentLocale]]];
    NSString *filename = [NSString stringWithFormat:@"Seohtracker %@.csv",
        [dateFormatter stringFromDate:[NSDate date]]];
    // Remove troublesome characters from generated path.
    for (NSString *invalid in @[@"/", @":", @"\\", @"?", @"*", @"\""]) {
        filename = [filename stringByReplacingOccurrencesOfString:invalid
            withString:@"-"];
    }

    return filename;
}

/** Starts a pseudo modal sheet and keeps track of it.
 *
 * The pointers are kept to be able to cancel the modal sheet should an
 * external event happen (like file importation). If there already was a modal
 * sheet, it is dismissed first. Opening a modal sheet disables the table view
 * to avoid scrolling.
 *
 * Returns the result of calling [NSApp runModalForWindow:].
 */
- (NSInteger)begin_modal_sheet:(NSWindow*)sheet_window
{
    [self end_modal_sheet];

    self.modal_sheet_window = sheet_window;
    self.table_view.enabled = NO;
    [NSApp beginSheet:sheet_window modalForWindow:[self.view window]
        modalDelegate:self didEndSelector:nil contextInfo:nil];
    return [NSApp runModalForWindow:sheet_window];
}

/** Dismisses a modal sheet previously opened with begin_modal_sheet.
 *
 * You can call this at any time, it will do nothing if there is no modal
 * sheet.
 */
- (void)end_modal_sheet
{
    self.table_view.enabled = YES;
    if (!self.modal_sheet_window)
        return;
    [NSApp endSheet:self.modal_sheet_window];
    [self.modal_sheet_window orderOut:self];
    self.modal_sheet_window = nil;
}

/// Default normal color for cell text.
- (NSColor*)normal_color
{
    return [NSColor blackColor];
}

/// Color for the text of cells using the same day.
- (NSColor*)shadowed_color
{
    return [NSColor grayColor];
}

/// Changes the background of the table row according to the weight attributes.
- (void)update_row_background:(NSTableRowView*)row_view for_row:(NSInteger)row
{
    TWeight *w = get_weight(row);
    RASSERT(w, @"No weight for position?", return);

    if (alternating_day(w)) {
        row_view.backgroundColor = [NSColor colorWithSRGBRed:237/255.0
            green:237/255.0 blue:1 alpha:1];
    } else {
        row_view.backgroundColor = [NSColor whiteColor];
    }
}

/** Call this after rows are reshuffled in the list.
 *
 * Visible rows will be iterated and their background color updated to the
 * logic model. This is usually done for added rows.
 */
- (void)refresh_row_backgrounds
{
    [self.table_view enumerateAvailableRowViewsUsingBlock:
        ^(NSTableRowView *v, NSInteger r) {
            [self update_row_background:v for_row:r];
        }];
}

#pragma mark -
#pragma mark EHGraph_click_delegate protocol

/// Called by the graph when the user clicks on it.
- (void)did_click_on_weight:(TWeight*)w
{
    [self select_table_pos:find_pos(w)];
    [self refresh_ui];
}

#pragma mark -
#pragma mark NSTableViewDataSource protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    DLOG(@"Got %lld weights in table", get_num_weights());
    return get_num_weights();
}

#pragma mark -
#pragma mark NSTableViewDelegate protocol

/// Overrides to change row background color.
- (void)tableView:(NSTableView *)tableView
    didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
    [self update_row_background:rowView for_row:row];
}

- (NSView*)tableView:(NSTableView*)tableView
    viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    // Get a new ViewCell
    NSTableCellView *cell = [tableView
        makeViewWithIdentifier:tableColumn.identifier owner:self];
    TWeight *w = get_weight(row);
    RASSERT(w, @"No weight for position?", return cell);

    if ([tableColumn.identifier isEqualToString:@"EHHistory_date"]) {
        if (changes_day(w)) {
            cell.textField.stringValue = format_relative_date(w);
        } else {
            cell.textField.attributedStringValue =
                format_shadowed_date(w, cell.textField.font,
                self.normal_color, self.shadowed_color);
        }
    } else if ([tableColumn.identifier isEqualToString:@"EHHistory_weight"]) {
        cell.textField.stringValue = [NSString
            stringWithFormat:@"%s %s", format_weight_with_current_unit(w),
            get_weight_string()];

        cell.textField.textColor = (changes_day(w) ?
            self.normal_color : self.shadowed_color);
    } else {
        LASSERT(0, @"Bad column");
    }
    return cell;
}

/// User clicked or moved the cursor, update the UI.
- (void)tableViewSelectionDidChange:(NSNotification*)aNotification
{
    [self refresh_ui];
}

#pragma mark -
#pragma mark NSMenuValidation protocol

/// Called by the UI to check the state of the menu entries.
- (BOOL)validateMenuItem:(NSMenuItem *)menu_item
{
    if (!menu_item.action)
        return NO;

#define _ACTION(SELNAME) ([menu_item action] == @selector(SELNAME))

    if (_ACTION(did_touch_plus_button:)) {
        return YES;
    } else if (_ACTION(did_touch_minus_button:) ||
            _ACTION(did_touch_modify_button:)) {
        TWeight *w = [self selected_weight];
        return (w ? YES : NO);
    } else {
        LASSERT(NO, @"Should not reach here. Probably.");
        return NO;
    }
#undef _ACTION
}

@end
