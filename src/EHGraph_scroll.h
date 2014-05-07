@protocol EHGraph_scroll_delegate <NSObject>
@end

/** Adds external methods to the normal NSScrollView.
 * This is just a more natural grouping of the code related to the graph.
 * The data is obtained through the delegate.
 */
@interface EHGraph_scroll : NSScrollView

- (void)resize_graph;

@end
