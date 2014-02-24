#import "EHHistory_vc.h"

#import "EHAppDelegate.h"

#import "ELHASO.h"

@interface EHHistory_vc ()

@property (weak) IBOutlet NSTableView *table_view;

@end

@implementation EHHistory_vc

- (id)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

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

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    DLOG(@"Got %lld weights in table", get_num_weights());
    return get_num_weights();
}

@end
