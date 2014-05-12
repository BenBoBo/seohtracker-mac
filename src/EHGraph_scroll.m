#import "EHGraph_scroll.h"

#import "ELHASO.h"
#import "NSBezierPath+Seohtracker.h"

#import <QuartzCore/QuartzCore.h>


#define _GRAPH_REDRAW_DELAY 0.5
#define _DAY_MODULUS (60 * 60 * 24)
#define _TICK_SPACE 15
#define _DAY_SCALE 15.0
#define _MIN_MAX_FONT_SIZE 16
#define _MIN_MAX_FONT_NAME @"Helvetica-Bold"
#define _MIN_MAX_FG_COL [NSColor blackColor]
#define _MIN_MAX_BG_COL [NSColor clearColor]

// Forward declarations.
static void get_curve_control_points(const CGPoint *knots, CGPoint *first_cp,
    CGPoint *second_cp, const long total_points);
static CGFloat *get_first_control_points(const CGFloat *rhs, const long n);


@interface EHGraph_scroll ()

/// Hooks the text layer used to infor the user we are working.
@property (nonatomic, weak) IBOutlet NSTextField *shield_view;
/// Our original graph layer which we update.
@property (strong) CAShapeLayer *graph_layer;
/// Keeps track of the previous (and future!) height.
@property (nonatomic, assign) int last_height;
/// Keeps track of the previous amount of entries used in the graph.
@property (nonatomic, assign) long last_data_points;
/// Layer with ticks and other marks for the graph.
@property (nonatomic, strong) CAShapeLayer *white_lines_layer;
/// Another layer with ticks and other marks for the graph.
@property (nonatomic, strong) CAShapeLayer *black_lines_layer;
/// Layer for the minimum weight.
@property (nonatomic, strong) CATextLayer *min_y_text_layer;
/// Layer for the maximum weight.
@property (nonatomic, strong) CATextLayer *max_y_text_layer;

@end


@implementation EHGraph_scroll

#pragma mark -
#pragma mark Life

/** Register notifications for frame changes so we can update the contents.
 */
- (void)awakeFromNib
{
    [super awakeFromNib];
    self.shield_view.alphaValue = 0;
    [self setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(frame_did_change:)
        name:NSViewFrameDidChangeNotification object:self];
}

/** Takes care of constructing the layers for the view.
 * This should be run only once if graph_layer (and others) is nil to fill it.
 */
- (void)init_properties
{
    LASSERT(!self.graph_layer, @"Double initialization?");
    LASSERT(self.documentView, @"No document view available?");

    self.backgroundColor = [NSColor whiteColor];
    // Create the layer for the graph content.
    CAShapeLayer *shape = [CAShapeLayer new];
    [shape setFillColor:[[NSColor redColor] CGColor]];
    [shape setStrokeColor:[[NSColor blackColor] CGColor]];
    [shape setLineWidth:2.f];
    [shape setOpacity:1];

    shape.shadowColor = [[NSColor blackColor] CGColor];
    shape.shadowRadius = 4.f;
    shape.shadowOffset = CGSizeMake(0, 0);
    shape.shadowOpacity = 0.8;

    NSView *doc = self.documentView;
    [doc.layer addSublayer:shape];
    self.graph_layer = shape;
    [self.documentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(content_did_change:)
        name:NSViewBoundsDidChangeNotification object:self.contentView];

    // Create the layer for the horizontal overlay lines.
    shape = [CAShapeLayer new];
    [shape setStrokeColor:[[NSColor whiteColor] CGColor]];
    [shape setLineWidth:0.5];
    [shape setOpacity:0.4];

    [doc.layer addSublayer:shape];
    self.white_lines_layer = shape;

    // Create the solid overlay for the visible ticks.
    shape = [CAShapeLayer new];
    [shape setStrokeColor:[[NSColor blackColor] CGColor]];
    [shape setLineWidth:0.5];
    [shape setOpacity:1];

    [doc.layer addSublayer:shape];
    self.black_lines_layer = shape;

    CATextLayer*(^build_text_layer)(void) = ^(void) {
        CATextLayer *l = [CATextLayer new];
        [l setFont:_MIN_MAX_FONT_NAME];
        [l setFontSize:_MIN_MAX_FONT_SIZE];
        [l setForegroundColor:[_MIN_MAX_FG_COL CGColor]];
        [l setBackgroundColor:[_MIN_MAX_BG_COL CGColor]];
        [l setOpacity:0.8];
        return l;
    };

    self.min_y_text_layer = build_text_layer();
    [doc.layer addSublayer:self.min_y_text_layer];

    self.max_y_text_layer = build_text_layer();
    [doc.layer addSublayer:self.max_y_text_layer];
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(do_resize_graph) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:NSViewBoundsDidChangeNotification object:nil];
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

    // Hide existing graphs/layers.
    [CATransaction begin];
    [CATransaction setAnimationDuration:_GRAPH_REDRAW_DELAY];
    self.min_y_text_layer.opacity = 0;
    self.max_y_text_layer.opacity = 0;
    self.graph_layer.opacity = 0;
    self.white_lines_layer.opacity = 0;
    self.black_lines_layer.opacity = 0;
    self.shield_view.animator.alphaValue = 1;
    [CATransaction commit];

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

    if (!self.graph_layer)
        [self init_properties];
    LASSERT(self.graph_layer, @"Bad initialization");

    // Recover hidden layers.
    self.min_y_text_layer.opacity = 1;
    self.max_y_text_layer.opacity = 1;
    self.graph_layer.opacity = 1;
    self.white_lines_layer.opacity = 1;
    self.black_lines_layer.opacity = 1;
    self.shield_view.animator.alphaValue = 0;

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

    // Calculate the min/max localized weight values.
    double min_weight = 0, max_weight = 0, weight_range = 1;
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
    }

    // Calculate the start/end of the y axis along with number of ticks.
    const int max_y_ticks = (graph_height - 2 * _TICK_SPACE) / _TICK_SPACE;
    Nice_scale *y_axis = malloc_scale(min_weight, max_weight, max_y_ticks);
    const double nice_y_min = scale_nice_min(y_axis);
    const double nice_y_max = scale_nice_max(y_axis);
    const double tick_y_spacing = scale_tick_spacing(y_axis);
    DLOG(@"Min weight %0.2f, max weight %0.2f", min_weight, max_weight);
    DLOG(@"nice min %0.2f, max %0.2f, spacing %0.2f",
        nice_y_min, nice_y_max, tick_y_spacing);
    // Update the graphic range to scale down the vertical axis.
    if (nice_y_max - nice_y_min >= 1)
        weight_range = nice_y_max - nice_y_min;

    // For the x axis we scale down the times to get days, then scale back
    // again to use in the future plotting calculation.
    Nice_scale *x_axis = malloc_scale(min_date / _DAY_MODULUS,
        max_date / _DAY_MODULUS, 0);
    const double nice_x_min = scale_nice_min(x_axis);
    const double nice_x_max = scale_nice_max(x_axis);
    const double nice_min_date = nice_x_min * _DAY_MODULUS;
    DLOG(@"Min date %ld, nicer min date %0.0f",
        min_date / _DAY_MODULUS, nice_x_min / _DAY_MODULUS);

    // Transform the real graph limits into *ideal* limits for axis ranges.
    LASSERT(weight_range >= 1, @"Ugh, bad y scale");
    const double h_factor = graph_height / weight_range;
    const double w_factor = _DAY_SCALE / ((double)_DAY_MODULUS);

    // Create bezier path.
    NSBezierPath *waveform = [NSBezierPath new];
    waveform.lineJoinStyle = kCGLineJoinRound;
    if (num_weights) {
        TWeight *w;
        CGPoint *knots = malloc(sizeof(CGPoint) * (num_weights + 2));
        CGPoint *p = knots + 1;

        // Build the knots, which are the weights plotted on the graph.
        for (int f = 0; f < num_weights; f++, p++) {
            w = get_weight(f);
            p->x = (date(w) - nice_min_date) * w_factor;
            p->y = (get_localized_weight(w) - nice_y_min) * h_factor;
            //DLOG(@"Got %0.1f with %0.1f", p->x, p->y);
        }

        // Fix the first entry, it's like the second with y = 0
        knots[0].x = knots[1].x;
        knots[0].y = 0;
        // Fix the last entry, it's like the previous with y = 0
        p->x = (p - 1)->x;
        p->y = 0;

        // Obtain control points.
        CGPoint *control1 = malloc(sizeof(CGPoint) * (num_weights + 1));
        CGPoint *control2 = malloc(sizeof(CGPoint) * (num_weights + 1));
        get_curve_control_points(knots, control1, control2, 2 + num_weights);

#if 1
        [waveform appendBezierPathWithPoints:knots count:num_weights + 2];
#else
        [waveform moveToPoint:knots[0]];
        p = knots + 1;
        CGPoint *c1 = control1, *c2 = control2;
        for (int f = 0; f < num_weights; f++, p++, c1++, c2++)
            [waveform curveToPoint:*p controlPoint1:*c1 controlPoint2:*c2];
        [waveform curveToPoint:*p controlPoint1:*c1 controlPoint2:*c2];
#endif
        free(knots);
        free(control1);
        free(control2);
    }
    DLOG(@"Got %ld total days, graph height %d", total_days, graph_height);

    const NSSize doc_size = NSMakeSize(
        (nice_x_max - nice_x_min) * _DAY_SCALE, graph_height);
    [self.documentView setFrameSize:doc_size];
    [self.graph_layer setPath:[waveform quartzPath]];

    [self build_axis_layer:x_axis y_axis:y_axis
        w_factor:_DAY_MODULUS * w_factor h_factor:h_factor];

    free_scale(x_axis);
    free_scale(y_axis);

    // Try to center a specific value?
    if (self.redraw_lock) {
        DLOG(@"Got a request to lock on %p", self.redraw_lock);
        NSClipView *clip = CAST(self.contentView, NSClipView);
        const CGFloat x = MIN(doc_size.width - self.bounds.size.width,
            (date(self.redraw_lock) - nice_min_date) * w_factor);
        if (x > 0)
            [clip scrollToPoint:CGPointMake(x, 0)];
        self.redraw_lock = nil;
    }
}

/** Builds the axis layer and replaces the instance variable.
 *
 * Pass the x and y axis scales and the factors to multiply units in each axis
 * to obtain actual plot values.
 *
 * Note that x values have to be multiplied by _DAY_MODULUS.
 */
- (void)build_axis_layer:(Nice_scale*)x_axis y_axis:(Nice_scale*)y_axis
    w_factor:(double)w_factor h_factor:(double)h_factor
{
    LASSERT(x_axis && y_axis, @"Bad parameters");
    LASSERT(self.white_lines_layer, @"Invalid class state");
    const double y_range = scale_nice_max(y_axis) - scale_nice_min(y_axis);
    const double x_range = scale_nice_max(x_axis) - scale_nice_min(x_axis);
    const double y_step = scale_tick_spacing(y_axis);

    // Create horizontal white lines.
    NSBezierPath *b = [NSBezierPath new];
    [b moveToPoint:CGPointMake(1, 1)];
    [b lineToPoint:CGPointMake(1, y_range * h_factor)];
    [b moveToPoint:CGPointMake(1, 1)];
    [b lineToPoint:CGPointMake(x_range * w_factor, 1)];
    double pos = 0;
    const double size = x_range * w_factor;
    for (int f = 0; pos <= y_range; f++) {
        pos = f * y_step;
        [b moveToPoint:CGPointMake(0, pos * h_factor)];
        [b lineToPoint:CGPointMake(size, pos * h_factor)];
    }

    [self.white_lines_layer setPath:[b quartzPath]];

    // Create axis and daily ticks.
    b = [NSBezierPath new];
    [b moveToPoint:CGPointMake(1, 1)];
    [b lineToPoint:CGPointMake(1, y_range * h_factor)];
    [b moveToPoint:CGPointMake(1, 1)];
    [b lineToPoint:CGPointMake(x_range * w_factor, 1)];

    // Start going back from the future, counting 7 days to make longer ticks.
    pos = x_range * w_factor;
    int count = 0;
    while (pos > 0) {
        [b moveToPoint:CGPointMake(pos, 1)];
        if ((count % 7) == 0)
            [b lineToPoint:CGPointMake(pos, y_step * h_factor)];
        else
            [b lineToPoint:CGPointMake(pos, 0.5 * y_step * h_factor)];
        pos -= w_factor;
        count++;
    }

    [self.black_lines_layer setPath:[b quartzPath]];

    NSDictionary *attributes = @{ NSFontAttributeName:
        [NSFont fontWithName:@"Helvetica-Bold" size:16] };

    NSString *text = [NSString stringWithFormat:@"%0.1f",
        scale_nice_min(y_axis)];

    NSRect rect;
    rect.origin.x = self.documentVisibleRect.origin.x;
    rect.size = [text sizeWithAttributes:attributes];
    [self.min_y_text_layer setFrame:rect];
    [self.min_y_text_layer setString:text];

    text = [NSString stringWithFormat:@"%0.1f",
        scale_nice_max(y_axis)];

    rect.size = [text sizeWithAttributes:attributes];
    rect.origin.y = self.bounds.size.height - rect.size.height;
    [self.max_y_text_layer setFrame:rect];
    [self.max_y_text_layer setString:text];
}

#pragma mark -
#pragma mark Scroll view callbacks/notifications

/** Invoked when the user scrolls stuff.
 * We use this callback to update the text layers so their position matches the
 * left frame and it looks as if they had not scrolled at all.
 */
- (void)content_did_change:(NSNotification*)notification
{
    NSClipView *v = CAST(notification.object, NSClipView);
    LASSERT(v, @"Bad object?");
    const CGFloat x = v.documentVisibleRect.origin.x;

    // Disable animations, otherwise there is a weird scrolling.
    [CATransaction begin];
    [CATransaction setAnimationDuration:0];
    NSRect rect = self.max_y_text_layer.frame;
    rect.origin.x = x;
    self.max_y_text_layer.frame = rect;

    rect = self.min_y_text_layer.frame;
    rect.origin.x = x;
    self.min_y_text_layer.frame = rect;
    [CATransaction commit];
}

/** Invoked when the view changes size.
 * We use this callback to request a content resize.
 */
- (void)frame_did_change:(NSNotification*)notification
{
    NSScrollView *s = CAST(notification.object, NSScrollView);
    LASSERT(s, @"Bad object?");
    //DLOG(@"Frame changed! %@", NSStringFromRect(s.frame));
    [self resize_graph];
}

@end

#pragma mark -
#pragma mark Static functions for bezier calculation

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
