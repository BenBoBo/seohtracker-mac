#import "EHHistory_vc.h"

#import "ELHASO.h"

@interface EHHistory_vc ()

@property (weak) IBOutlet NSTableView *table_view;

@end

@implementation EHHistory_vc

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)awakeFromNib
{
    DLOG(@"Hey there!");
}
@end
