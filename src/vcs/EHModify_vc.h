#import "n_global.h"

@interface EHModify_vc : NSWindowController

/// Set this to the weight modified.
- (void)set_values_from:(TWeight*)weight for_new_value:(BOOL)for_new_value;

- (NSDate*)accepted_date;
- (float)accepted_weight;

@end
