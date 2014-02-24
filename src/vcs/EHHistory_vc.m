#import "EHHistory_vc.h"

#import "EHApp_delegate.h"

#import "ELHASO.h"

@interface EHHistory_vc ()

@property (weak) IBOutlet NSTableView *table_view;
/// Holds a read only text for the selected date.
@property (weak) IBOutlet NSTextField *read_date_textfield;
/// Holds a read only text for the selected weight.
@property (weak) IBOutlet NSTextField *read_weight_textfield;

@end

@implementation EHHistory_vc

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
    DLOG(@"Awakening!");
    [self refresh_ui];
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
    } else {
        self.read_date_textfield.stringValue = @"";
        self.read_weight_textfield.stringValue = @"";
    }
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
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    [self refresh_ui];
}

@end
