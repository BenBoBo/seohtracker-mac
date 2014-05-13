#import "n_global.h"

@class EHGraph_scroll;

@protocol EHGraph_click_delegate <NSObject>

- (void)did_click_on_weight:(TWeight*)weight;

@end

/** Adds external methods to the normal NSScrollView.
 * This is just a more natural grouping of the code related to the graph.
 */
@interface EHGraph_scroll : NSScrollView

/// Set to a weight you want to have visible during the next content redraw.
@property (nonatomic, assign) TWeight *redraw_lock;

/// Set to a delegate to get callbacks about clicks.
@property (nonatomic, weak) id<EHGraph_click_delegate> click_delegate;

- (void)select_weight:(TWeight*)weight;

@end
