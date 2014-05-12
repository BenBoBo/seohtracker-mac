#import "n_global.h"

/** Adds external methods to the normal NSScrollView.
 * This is just a more natural grouping of the code related to the graph.
 */
@interface EHGraph_scroll : NSScrollView

/// Set to a weight you want to have visible during the next content redraw.
@property (nonatomic, assign) TWeight *redraw_lock;

@end
