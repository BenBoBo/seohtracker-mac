#import "EHGraph_scroll.h"

#import "ELHASO.h"
#import "NSBezierPath+Seohtracker.h"

#import <QuartzCore/QuartzCore.h>


#define _GRAPH_REDRAW_DELAY 0.5


@interface EHGraph_scroll ()

/// Our original graph layer which we update.
@property (strong) CAShapeLayer *graph_layer;

/// Stores the future size for the graph_layer after delayed resizing kicks in.
@property (nonatomic, assign) int future_graph_height;

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

/** Initial testing of graph scrolling
 *
 * Sets up a not very correct graph just for testing.
 */
#define W 600

- (void)resize_graph
{
    const int height = self.bounds.size.height;

    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(do_resize_graph) object:nil];

    self.future_graph_height = height;
    [self performSelector:@selector(do_resize_graph)
        withObject:nil afterDelay:_GRAPH_REDRAW_DELAY];
}

/** Workhorse invoked after a delay by resize_graph:
 *
 * It takes the new height from the future_graph_height value.
 */
- (void)do_resize_graph
{
    const int height = self.future_graph_height;

    if (!self.graph_layer) {
        self.backgroundColor = [NSColor whiteColor];
        // Create graph layer.
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
