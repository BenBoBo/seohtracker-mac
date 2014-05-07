#import "EHGraph_scroll.h"

#import "ELHASO.h"
#import "NSBezierPath+Seohtracker.h"

#import <QuartzCore/QuartzCore.h>


#define _GRAPH_REDRAW_DELAY 0.5


@interface EHGraph_scroll ()

/// Our original graph layer which we update.
@property (strong) CAShapeLayer *graph_layer;

/// Keeps track of the previous (and future!) height.
@property (nonatomic, assign) int last_height;

@end


@implementation EHGraph_scroll

#pragma mark -
#pragma mark Life

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(do_resize_graph) object:nil];
}

#pragma mark -
#pragma mark Methods

/** Requests the graph to resize its contents to match the scroll view frame.
 *
 * You can call this at any time as much as you want. It will queue a pending
 * operation to regenerate the graph, and only if the new height is different
 * than the old one.
 */
#define W 600

- (void)resize_graph
{
    const int new_height = self.bounds.size.height;
    if (new_height == self.last_height)
        return;

    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(do_resize_graph) object:nil];

    self.last_height = MAX(1, new_height);
    [self performSelector:@selector(do_resize_graph)
        withObject:nil afterDelay:_GRAPH_REDRAW_DELAY];
}

/** Workhorse invoked after a delay by resize_graph.
 *
 * It takes the new height from the last_height value.
 */
- (void)do_resize_graph
{
    DLOG(@"do_resize_graph");
    const int height = self.last_height;
    LASSERT(height > 0, @"Bad requested height, should always be positive");

    if (!self.graph_layer) {
        // Create graph layer.
        self.backgroundColor = [NSColor whiteColor];
        CAShapeLayer *graph_layer = [CAShapeLayer new];
        [graph_layer setFillColor:[[NSColor redColor] CGColor]];
        [graph_layer setStrokeColor:[[NSColor blackColor] CGColor]];
        [graph_layer setLineWidth:2.f];
        [graph_layer setOpacity:0.4];

        graph_layer.shadowColor = [[NSColor blackColor] CGColor];
        graph_layer.shadowRadius = 4.f;
        graph_layer.shadowOffset = CGSizeMake(0, 0);
        graph_layer.shadowOpacity = 0.8;

        NSView *doc = self.documentView;
        [doc.layer addSublayer:graph_layer];
        self.graph_layer = graph_layer;
    }

    // Create bezier path.
    NSBezierPath *waveform = [[NSBezierPath alloc] init];
    [waveform moveToPoint:CGPointMake(0.f, 1.f)];
    for (int i = 0; i < W; i++)
        [waveform lineToPoint:CGPointMake(i, random() % height)];
    [waveform lineToPoint:CGPointMake(W, 1.f)];

    [self.documentView setFrameSize:NSMakeSize(W, height)];
    [self.graph_layer setPath:[waveform quartzPath]];
}

@end
