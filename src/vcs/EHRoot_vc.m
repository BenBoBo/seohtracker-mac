#import "EHRoot_vc.h"

#import "EHApp_delegate.h"
#import "EHModify_vc.h"

#import "ELHASO.h"
#import "NSNotificationCenter+ELHASO.h"


@interface EHRoot_vc ()

@property (nonatomic, weak) IBOutlet NSTableView *table_view;
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

- (IBAction)did_touch_modify_button:(id)sender;
- (IBAction)did_touch_minus_button:(id)sender;
- (IBAction)did_touch_plus_button:(id)sender;

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

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center refresh_observer:self selector:@selector(refresh_ui_observer:)
            name:user_metric_prefereces_changed object:nil];
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
            stringWithFormat:@"Date: %@", format_date(w)];
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
}

/// Simple wrapper to refresh the UI when changes are done to user settings.
- (void)refresh_ui_observer:(NSNotification*)notification
{
    const NSInteger pos = [self.table_view selectedRow];
    [self refresh_ui];
    [self.table_view reloadData];
    // Attempt to recover previous row selection.
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
        initWithWindowNibName:NSStringFromClass([EHModify_vc class])];
    [vc set_values_from:weight for_new_value:NO];

    // Display modal sheet, disable our table view.
    self.table_view.enabled = NO;
    [NSApp beginSheet:vc.window modalForWindow:[self.view window]
        modalDelegate:self didEndSelector:nil contextInfo:nil];
    const NSInteger ret = [NSApp runModalForWindow: vc.window];
    [NSApp endSheet:vc.window];
    [vc.window orderOut:self];
    self.table_view.enabled = YES;

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
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSetWithIndex:new_pos];
    if (old_pos != new_pos) [rows addIndex:old_pos];
    [self.table_view reloadDataForRowIndexes:rows
        columnIndexes:[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, 2}]];

    // Force selection to the new position.
    [rows removeAllIndexes];
    [rows addIndex:new_pos];
    [self.table_view deselectAll:self];
    [self.table_view selectRowIndexes:rows byExtendingSelection:NO];
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
        format_date(weight)];
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
        [self.table_view removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:pos]
            withAnimation:NSTableViewAnimationSlideLeft];
    }
}

/// Adds a new entry, displaying the modification sheet.
- (IBAction)did_touch_plus_button:(id)sender
{
    EHModify_vc *vc = [[EHModify_vc alloc]
        initWithWindowNibName:NSStringFromClass([EHModify_vc class])];
    [vc set_values_from:get_last_weight() for_new_value:YES];

    // Display modal sheet, disable our table view.
    self.table_view.enabled = NO;
    [NSApp beginSheet:vc.window modalForWindow:[self.view window]
        modalDelegate:self didEndSelector:nil contextInfo:nil];
    const NSInteger ret = [NSApp runModalForWindow: vc.window];
    [NSApp endSheet:vc.window];
    [vc.window orderOut:self];
    self.table_view.enabled = YES;

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
    NSIndexSet *row = [NSIndexSet indexSetWithIndex:new_pos];
    [self.table_view insertRowsAtIndexes:row
        withAnimation:NSTableViewAnimationSlideRight];

    // Force selection to the new position.
    [self.table_view deselectAll:self];
    [self.table_view selectRowIndexes:row byExtendingSelection:NO];
    [self animate_scroll_to:new_pos];
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
    NSString *path = [url path];
    DLOG(@"Would be reading %@", path);

    NSWindowController *wc = [[NSWindowController alloc]
        initWithWindowNibName:@"EHProgress_sheet"];
    NSWindow *sheet = wc.window;

    [NSApp beginSheet:sheet modalForWindow:[self.view window]
        modalDelegate:nil didEndSelector:NULL contextInfo:NULL];

    [sheet makeKeyAndOrderFront:self];

    // Start computation using GCD...
    const int maxloop = 200;
    for (int i = 0; i < maxloop; i++) {

        [NSThread sleepForTimeInterval:0.01];
        DLOG(@"step %d", i);
    }

    [NSApp endSheet:sheet];
    [sheet orderOut:self];
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

- (NSView*)tableView:(NSTableView*)tableView
    viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    // Get a new ViewCell
    NSTableCellView *cellView = [tableView
        makeViewWithIdentifier:tableColumn.identifier owner:self];
    TWeight *w = get_weight(row);
    RASSERT(w, @"No weight for position?", return cellView);

    if ([tableColumn.identifier isEqualToString:@"EHHistory_date"]) {
        cellView.textField.stringValue = format_date(w);
    } else if ([tableColumn.identifier isEqualToString:@"EHHistory_weight"]) {
        cellView.textField.stringValue = [NSString
            stringWithFormat:@"%s %s", format_weight_with_current_unit(w),
            get_weight_string()];
    } else {
        LASSERT(0, @"Bad column");
    }
    return cellView;
}

/// User clicked or moved the cursor, update the UI.
- (void)tableViewSelectionDidChange:(NSNotification*)aNotification
{
    [self refresh_ui];
}

@end
