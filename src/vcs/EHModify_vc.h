#import "n_global.h"

@interface EHModify_vc : NSWindowController

/// Set this to the weight modified.
- (void)set_values_from:(TWeight*)weight;

- (NSDate*)accepted_date;
- (float)accepted_weight;

@end
