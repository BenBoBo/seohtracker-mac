#import "EHHistory_vc.h"

#import "n_global.h"

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

- (void)awakeFromNib
{
    DLOG(@"Awakening…");
}

- (NSView*)tableView:(NSTableView*)tableView
    viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    // Get a new ViewCell
    NSTableCellView *cellView = [tableView
        makeViewWithIdentifier:tableColumn.identifier owner:self];

    if ([tableColumn.identifier isEqualToString:@"EHHistory_date"]) {
    } else if ([tableColumn.identifier isEqualToString:@"EHHistory_weight"]) {
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
