#import "EHGraph_scroll.h"

#import "n_global.h"

#import "ELHASO.h"
#import "NSBezierPath+Seohtracker.h"

#import <QuartzCore/QuartzCore.h>


#define _GRAPH_REDRAW_DELAY 0.5
#define _DAY_MODULUS (60 * 60 * 24)


@interface EHGraph_scroll ()

/// Our original graph layer which we update.
@property (strong) CAShapeLayer *graph_layer;
/// Keeps track of the previous (and future!) height.
@property (nonatomic, assign) int last_height;
/// Keeps track of the previous amount of entries used in the graph.
@property (nonatomic, assign) long last_data_points;

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
 *
 * You should call this if the size of the frame for the scrollview changes, or
 * the logic data is modified (additions, modifications or deletions).
 */
- (void)resize_graph
{
    const int new_height = self.bounds.size.height;
    const long new_data_points = get_num_weights();
    // Check if we have to update the graph.
    if (new_height == self.last_height &&
            new_data_points == self.last_data_points ) {
        return;
    }

    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(do_resize_graph) object:nil];

    self.last_height = MAX(1, new_height);
    self.last_data_points = new_data_points;

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

    const long num_weights = get_num_weights();
    const int graph_height = self.last_height;

    // Calculate the width of the graph. This can be done taking the distance
    // in days between the first and last entries.
    time_t min_date = 0, max_date = _DAY_MODULUS;
    if (num_weights) {
        min_date = date(get_weight(0));
        max_date += date(get_last_weight());
    }
    LASSERT(max_date > min_date, @"Bad calculations, max should be bigger");
    const long total_days = (max_date - min_date) / _DAY_MODULUS;
    double day_scale = 15;

    // Calculate the min/max localized weight values.
    double min_weight = 0, max_weight = 0, weight_range = 0;
    if (num_weights) {
        max_weight = min_weight = get_localized_weight(get_weight(0));
        for (int f = 1; f < num_weights; f++) {
            const double w = get_localized_weight(get_weight(f));
            max_weight = MAX(max_weight, w);
            min_weight = MIN(min_weight, w);
        }
        // Now calculate the weight range between the extremes, expand it a
        // little bit, and reduce slightly the min_weight so it serves as base
        // starting point.
        weight_range = max_weight - min_weight;
        LASSERT(weight_range >= 0, @"Incorrect weight range");
        min_weight -= weight_range * 0.1;
        weight_range *= 1.2;
    }
    const double h_factor = graph_height / weight_range;

    // Create bezier path.
    NSBezierPath *waveform = [NSBezierPath new];
    waveform.lineJoinStyle = kCGLineJoinRound;
    if (num_weights) {
        TWeight *w;
        // Set the initial point of the graph.
        [waveform moveToPoint:CGPointMake(0.f, 0)];

        for (int f = 0; f < num_weights; f++) {
            w = get_weight(f);
            const double x = ((date(w) - min_date) / ((double)_DAY_MODULUS)) *
                day_scale;
            const double y = (get_localized_weight(w) - min_weight) * h_factor;
            DLOG(@"Got %0.1f with %0.1f", x, y);
            [waveform lineToPoint:CGPointMake(x, y)];
        }

        // Finish the graph.
        [waveform lineToPoint:CGPointMake(total_days * day_scale, 0)];
    }
    DLOG(@"Got %ld total days, graph height %d", total_days, graph_height);

    [self.documentView
        setFrameSize:NSMakeSize(total_days * day_scale, graph_height)];
    [self.graph_layer setPath:[waveform quartzPath]];
}

@end
