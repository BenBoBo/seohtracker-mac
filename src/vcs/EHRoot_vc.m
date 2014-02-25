#import "EHRoot_vc.h"

#import "EHApp_delegate.h"
#import "EHModify_vc.h"

#import "ELHASO.h"

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

- (IBAction)did_touch_modify_button:(id)sender;

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
    }
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
    } else {
        self.read_date_textfield.stringValue = @"";
        self.read_weight_textfield.stringValue = @"";
        self.modify_button.enabled = NO;
    }
}

/// Called when the user wants to modify an existing value.
- (IBAction)did_touch_modify_button:(id)sender
{
    TWeight *weight = [self selected_weight];
    EHModify_vc *vc = [[EHModify_vc alloc]
        initWithWindowNibName:NSStringFromClass([EHModify_vc class])];
    [vc set_values_from:weight];

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
