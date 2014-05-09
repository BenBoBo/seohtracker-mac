#import "EHGraph_scroll.h"

#import "n_global.h"

#import "ELHASO.h"
#import "NSBezierPath+Seohtracker.h"

#import <QuartzCore/QuartzCore.h>


#define _GRAPH_REDRAW_DELAY 0.5
#define _DAY_MODULUS (60 * 60 * 24)


// Forward declarations.
static void get_curve_control_points(const CGPoint *knots, CGPoint *first_cp,
    CGPoint *second_cp, const long total_points);
static CGFloat *get_first_control_points(const CGFloat *rhs, const long n);


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
        CGPoint *knots = malloc(sizeof(CGPoint) * (num_weights + 2));
        CGPoint *p = knots;

        // Build the knots, which are the weights plotted on the graph.
        p->x = p->y = 0;
        p++;

        for (int f = 0; f < num_weights; f++, p++) {
            w = get_weight(f);
            p->x = ((date(w) - min_date) / ((double)_DAY_MODULUS)) * day_scale;
            p->y = (get_localized_weight(w) - min_weight) * h_factor;
            //DLOG(@"Got %0.1f with %0.1f", x, y);
        }

        p->x = total_days * day_scale;
        p->y = 0;

        // Obtain control points.
        CGPoint *control1 = malloc(sizeof(CGPoint) * (num_weights + 1));
        CGPoint *control2 = malloc(sizeof(CGPoint) * (num_weights + 1));
        get_curve_control_points(knots, control1, control2, 2 + num_weights);

        //[waveform appendBezierPathWithPoints:knots count:num_weights + 2];
        [waveform moveToPoint:knots[0]];
        p = knots + 1;
        CGPoint *c1 = control1, *c2 = control2;
        for (int f = 0; f < num_weights; f++, p++, c1++, c2++)
            [waveform curveToPoint:*p controlPoint1:*c1 controlPoint2:*c2];
        [waveform curveToPoint:*p controlPoint1:*c1 controlPoint2:*c2];
        free(knots);
        free(control1);
        free(control2);
    }
    DLOG(@"Got %ld total days, graph height %d", total_days, graph_height);

    [self.documentView
        setFrameSize:NSMakeSize(total_days * day_scale, graph_height)];
    [self.graph_layer setPath:[waveform quartzPath]];
}

@end

/** Calculates the control points for the bezier *knots*.
 *
 * Pass the input knot bezier spline points. These are where the bezier spline
 * will go through, the control points will be generated for each segment and
 * placed in the output arrays.
 *
 * The first_cp and second_cp parameters have to be already allocated and
 * contain total_points - 1 entries.
 *
 * Algorithm and code adapted from
 * http://www.codeproject.com/Articles/31859/Draw-a-Smooth-Curve-through-a-Set-of-2D-Points-wit
 */
static void get_curve_control_points(const CGPoint *knots, CGPoint *first_cp,
    CGPoint *second_cp, const long total_points)
{
    assert(knots);
    const long n = total_points - 1;
    assert(n >= 1);

    if (n == 1) {
        // Special case: Bezier curve should be a straight line.
        // 3P1 = 2P0 + P3
        first_cp[0].x = (2 * knots[0].x + knots[1].x) / 3.0f;
        first_cp[0].y = (2 * knots[0].y + knots[1].y) / 3.0f;

        // P2 = 2P1 – P0
        second_cp[0].x = 2 * first_cp[0].x - knots[0].x;
        second_cp[0].y = 2 * first_cp[0].y - knots[0].y;
        return;
    }

    // Calculate first Bezier control points
    // Right hand side vector
    CGFloat rhs[n];
    // Set right hand side X values
    for (int i = 1; i < n - 1; ++i)
        rhs[i] = 4 * knots[i].x + 2 * knots[i + 1].x;

    rhs[0] = knots[0].x + 2 * knots[1].x;
    rhs[n - 1] = (8 * knots[n - 1].x + knots[n].x) / 2.0;
    // Get first control points X-values
    CGFloat *x = get_first_control_points(rhs, n);

    // Set right hand side Y values
    for (int i = 1; i < n - 1; ++i)
        rhs[i] = 4 * knots[i].y + 2 * knots[i + 1].y;
    rhs[0] = knots[0].y + 2 * knots[1].y;
    rhs[n - 1] = (8 * knots[n - 1].y + knots[n].y) / 2.0;
    // Get first control points Y-values
    CGFloat *y = get_first_control_points(rhs, n);

    // Fill output arrays.
    for (int i = 0; i < n; ++i) {
        // First control point
        first_cp[i].x = x[i];
        first_cp[i].y = y[i];
        // Second control point
        if (i < n - 1) {
            second_cp[i].x = 2 * knots[i + 1].x - x[i + 1];
            second_cp[i].y = 2 * knots[i + 1].y - y[i + 1];
        } else {
            second_cp[i].x = (knots[n].x + x[n - 1]) / 2;
            second_cp[i].y = (knots[n].y + y[n - 1]) / 2;
        }
    }
    free(x);
    free(y);
}

/** Helper to get control points.
 * Solves a tridiagonal system for one of coordinates (x or y) of first
 * Bezier control points. Pass the right hand side vector array.
 * Returns the solution vector you need to free.
 */
static CGFloat *get_first_control_points(const CGFloat *rhs, const long n)
{
    CGFloat *x = malloc(sizeof(CGFloat) * n); // Solution vector.
    CGFloat tmp[n]; // Temp workspace.

    CGFloat b = 2.0;
    x[0] = rhs[0] / b;
    for (int i = 1; i < n; i++) {
        // Decomposition and forward substitution.
        tmp[i] = 1 / b;
        b = (i < n - 1 ? 4.0 : 3.5) - tmp[i];
        x[i] = (rhs[i] - x[i - 1]) / b;
    }
    for (int i = 1; i < n; i++)
        x[n - i - 1] -= tmp[n - i] * x[n - i]; // Backsubstitution.

    return x;
}
