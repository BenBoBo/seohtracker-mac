#import "EHGraph_scroll.h"

#import "CAShapeLayer+Seohtracker.h"
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
#define _GRAPH_COLOR [NSColor colorWithSRGBRed:255/255.0 \
    green:174/255.0 blue:0 alpha:0.9]

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
/// Layer controlling the vertical highlighting of a weight.
@property (nonatomic, strong) CAShapeLayer *selection_x_layer;
/// Layer controlling the horizontal highlighting of a weight.
@property (nonatomic, strong) CAShapeLayer *selection_y_layer;

// Keeps the parameters required to calculate the X position of a graph.
@property (nonatomic, assign) double graph_min_date;
@property (nonatomic, assign) double graph_w_factor;
@property (nonatomic, assign) double graph_total_height;
@property (nonatomic, assign) double graph_min_weight;
@property (nonatomic, assign) double graph_h_factor;
@property (nonatomic, assign) double graph_total_width;

// Offsets to center the graphic if there is not enough data.
@property (nonatomic, assign) double offset_x;
@property (nonatomic, assign) double offset_y;

@end


@implementation EHGraph_scroll

#pragma mark -
#pragma mark Life

/** Register notifications for frame changes so we can update the contents.
 */
- (void)awakeFromNib
{
    [super awakeFromNib];
    // Hide the shield and make it ignore clicks, letting them through.
    self.shield_view.alphaValue = 0;
    self.shield_view.hidden = YES;
    NSRect rect = self.frame;
    [self.documentView setFrameSize:rect.size];
    [self setPostsFrameChangedNotifications:YES];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(frame_did_change:)
        name:NSViewFrameDidChangeNotification object:self];
    [center addObserver:self selector:@selector(scroller_did_change:)
        name:NSPreferredScrollerStyleDidChangeNotification object:nil];
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
    [shape setFillColor:[_GRAPH_COLOR CGColor]];
    [shape setStrokeColor:[[NSColor blackColor] CGColor]];
    [shape setLineWidth:2.f];

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
    [shape setStrokeColor:[[[NSColor whiteColor]
        colorWithAlphaComponent:0.5] CGColor]];
    [shape setLineWidth:0.5];

    [doc.layer addSublayer:shape];
    self.white_lines_layer = shape;

    // Create the solid overlay for the visible ticks.
    shape = [CAShapeLayer new];
    [shape setStrokeColor:[[NSColor blackColor] CGColor]];
    [shape setLineWidth:0.5];

    [doc.layer addSublayer:shape];
    self.black_lines_layer = shape;

    // Similar for the selection.
    shape = [CAShapeLayer new];
    [shape setStrokeColor:[[[NSColor blueColor]
        colorWithAlphaComponent:0.3] CGColor]];
    [shape setLineWidth:_DAY_SCALE * 0.5];

    [doc.layer addSublayer:shape];
    self.selection_x_layer = shape;

    // The horizontal selection is very much like a white line, only using a
    // more notable color.

    shape = [CAShapeLayer new];
    [shape setStrokeColor:[[[NSColor blackColor]
        colorWithAlphaComponent:0.4] CGColor]];
    [shape setLineWidth:0.5];

    [doc.layer addSublayer:shape];
    self.selection_y_layer = shape;

    CATextLayer*(^build_text_layer)(void) = ^(void) {
        CATextLayer *l = [CATextLayer new];
        [l setFont:_MIN_MAX_FONT_NAME];
        [l setFontSize:_MIN_MAX_FONT_SIZE];
        [l setForegroundColor:[[_MIN_MAX_FG_COL
            colorWithAlphaComponent:0.6] CGColor]];
        [l setBackgroundColor:[_MIN_MAX_BG_COL CGColor]];
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
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self
        name:NSViewBoundsDidChangeNotification object:nil];
    [center removeObserver:self
        name:NSPreferredScrollerStyleDidChangeNotification object:nil];
}

#pragma mark -
#pragma mark Properties

/// Overrides setter to immediately redraw the new value.
- (void)setSelected_weight:(TWeight*)weight
{
    _selected_weight = weight;
    [self select_weight:weight];
}

#pragma mark -
#pragma mark Methods

// Returns the bounds width minus scroller size.
- (CGFloat)visible_w
{
    const CGFloat w = self.bounds.size.width;
    const NSScrollerStyle s = [self scrollerStyle];
    if (NSScrollerStyleOverlay == s || ![self hasVerticalScroller])
        return w;
    const NSControlSize cs = [self.verticalScroller controlSize];
    CGFloat sw = [NSScroller scrollerWidthForControlSize:cs scrollerStyle:s];
    return w - sw;
}

// Returns the bounds height minus scroller size.
- (CGFloat)visible_h
{
    const CGFloat h = self.bounds.size.height;
    const NSScrollerStyle s = [self scrollerStyle];
    if (NSScrollerStyleOverlay == s || ![self hasHorizontalScroller])
        return h;
    const NSControlSize cs = [self.horizontalScroller controlSize];
    CGFloat sw = [NSScroller scrollerWidthForControlSize:cs scrollerStyle:s];
    return h - sw;
}

/** Requests the graph to resize its contents to match the scroll view frame.
 *
 * You can call this at any time as much as you want. It will queue a pending
 * operation to regenerate the graph, and only if the new height is different
 * than the old one.
 *
 * You should call this if the size of the frame for the scrollview changes, or
 * the logic data is modified (additions, modifications or deletions).
 */
- (void)refresh_graph
{
    const int new_height = [self visible_h];
    const long new_data_points = get_num_weights();
    // Check if we have to update the graph.
    // Patched to avoid weird scroll content view issues.
    //if (new_height == self.last_height &&
    //        new_data_points == self.last_data_points ) {
    //    return;
    //}

    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(do_resize_graph) object:nil];

    // Hide existing graphs/layers.
    self.shield_view.hidden = NO;
    [CATransaction begin];
    [CATransaction setAnimationDuration:_GRAPH_REDRAW_DELAY];
    self.min_y_text_layer.opacity = 0;
    self.max_y_text_layer.opacity = 0;
    self.graph_layer.opacity = 0;
    self.white_lines_layer.opacity = 0;
    self.black_lines_layer.opacity = 0;
    self.selection_x_layer.opacity = 0;
    self.selection_y_layer.opacity = 0;
    self.shield_view.animator.alphaValue = 1;
    [CATransaction commit];

    self.last_height = MAX(1, new_height);
    self.last_data_points = new_data_points;

    [self performSelector:@selector(do_resize_graph)
        withObject:nil afterDelay:_GRAPH_REDRAW_DELAY];
}

/** Workhorse invoked after a delay by refresh_graph.
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
    [CATransaction begin];
    [CATransaction setAnimationDuration:_GRAPH_REDRAW_DELAY];
    self.min_y_text_layer.opacity = 1;
    self.max_y_text_layer.opacity = 1;
    self.graph_layer.opacity = 1;
    self.white_lines_layer.opacity = 1;
    self.black_lines_layer.opacity = 1;
    self.selection_x_layer.opacity = 1;
    self.selection_y_layer.opacity = 1;
    self.shield_view.animator.alphaValue = 0;
    [CATransaction commit];

    RUN_AFTER(_GRAPH_REDRAW_DELAY, ^{
            self.shield_view.hidden = YES;
        });

    const long num_weights = get_num_weights();
    const int view_h = self.last_height;
    const int view_w = [self visible_w];

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
        weight_range = MAX(1, max_weight - min_weight);
    }

    // Calculate the start/end of the y axis along with number of ticks.
    const int max_y_ticks = (view_h - 2 * _TICK_SPACE) / _TICK_SPACE;
    Nice_scale *y_axis = (!num_weights ? nil :
        malloc_scale(min_weight, max_weight, max_y_ticks));
    const double nice_y_min = scale_nice_min(y_axis);
    const double nice_y_max = scale_nice_max(y_axis);
    const double tick_y_spacing = scale_tick_spacing(y_axis);
    DLOG(@"Min weight %0.2f, max weight %0.2f", min_weight, max_weight);
    DLOG(@"nice min %0.2f, max %0.2f, spacing %0.2f",
        nice_y_min, nice_y_max, tick_y_spacing);
    // Update the graphic range to scale down the vertical axis.
    if (nice_y_max - nice_y_min >= 1)
        weight_range = nice_y_max - nice_y_min;

    LASSERT(weight_range >= 1, @"Ugh, bad y scale");
    double h_factor = _DAY_SCALE * 3;
    self.offset_y = 0;
    // If the graph is small, add an offset. Otherwise scale down the h_factor.
    if (weight_range * h_factor < view_h)
        self.offset_y = (view_h - weight_range * h_factor) * 0.5;
    else
        h_factor = view_h / weight_range;

    // For the x axis we scale down the times to get days, then scale back
    // again to use in the future plotting calculation.
    Nice_scale *x_axis = (!num_weights ? nil :
        malloc_scale(min_date / _DAY_MODULUS, max_date / _DAY_MODULUS, 0));
    const double nice_x_min = scale_nice_min(x_axis);
    const double nice_x_max = scale_nice_max(x_axis);
    const double nice_min_date = nice_x_min * _DAY_MODULUS;
    DLOG(@"Min date %ld, nicer min date %0.0f",
        min_date / _DAY_MODULUS, nice_x_min / _DAY_MODULUS);

    // Transform the real graph limits into *ideal* limits for axis ranges.
    const double w_factor = _DAY_SCALE / ((double)_DAY_MODULUS);
    const double graph_width = (nice_x_max - nice_x_min) * _DAY_SCALE;
    self.offset_x = 0;
    if (graph_width < view_w)
        self.offset_x = (view_w - graph_width) * 0.5;

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
            p->x = self.offset_x + (date(w) - nice_min_date) * w_factor;
            p->y = (get_localized_weight(w) - nice_y_min) * h_factor +
                self.offset_y;
            //DLOG(@"Got %0.1f with %0.1f", p->x, p->y);
        }

        // Fix the first entry, it's like the second with y = 0
        knots[0].x = knots[1].x;
        knots[0].y = self.offset_y;
        // Fix the last entry, it's like the previous with y = 0
        p->x = (p - 1)->x;
        p->y = self.offset_y;

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
    DLOG(@"Got %ld total days, graph height %d", total_days, view_h);

    [self.documentView setFrameSize:NSMakeSize(graph_width, view_h)];
    [self.graph_layer setQuartzPath:waveform];

    [self build_axis_layer:x_axis y_axis:y_axis
        w_factor:_DAY_MODULUS * w_factor h_factor:h_factor];

    free_scale(x_axis);
    free_scale(y_axis);

    self.graph_min_date = nice_min_date;
    self.graph_w_factor = w_factor;
    self.graph_total_height = (nice_y_max - nice_y_min) * h_factor;
    self.graph_min_weight = nice_y_min;
    self.graph_h_factor = h_factor;
    self.graph_total_width = (nice_x_max - nice_x_min) *
        _DAY_MODULUS * w_factor;

    // Try to center a specific value?
    if (self.redraw_lock) {
        DLOG(@"Got a request to lock on %p", self.redraw_lock);
        NSClipView *clip = CAST(self.contentView, NSClipView);
        const CGFloat x = MIN(graph_width - view_w,
            (date(self.redraw_lock) - nice_min_date) * w_factor);
        if (x > 0) {
            [clip scrollToPoint:CGPointMake(x, 0)];
            [self reflectScrolledClipView:clip];
        }
        self.redraw_lock = nil;
    }

    // Refresh selection on the graph.
    [self select_weight:self.selected_weight];
}

/** Builds the axis layer and replaces the instance variable.
 *
 * Pass the x and y axis scales and the factors to multiply units in each axis
 * to obtain actual plot values.
 *
 * Note that x values have to be multiplied by _DAY_MODULUS.
 *
 * If x_axis or y_axis are nil, the scales will be reset to invisible values.
 */
- (void)build_axis_layer:(Nice_scale*)x_axis y_axis:(Nice_scale*)y_axis
    w_factor:(double)w_factor h_factor:(double)h_factor
{
    LASSERT(self.white_lines_layer, @"Invalid class state");
    const double y_range = scale_nice_max(y_axis) - scale_nice_min(y_axis);
    const double x_range = scale_nice_max(x_axis) - scale_nice_min(x_axis);
    const double y_step = scale_tick_spacing(y_axis);

    // Create horizontal white lines.
    NSBezierPath *b = [NSBezierPath new];
    if (x_axis && y_axis) {
        //[b moveToPoint:CGPointMake(1, 1)];
        //[b lineToPoint:CGPointMake(1, self.offset_y + y_range * h_factor)];
        //[b moveToPoint:CGPointMake(1, 1)];
        //[b lineToPoint:CGPointMake(x_range * w_factor, 1)];
        double pos = 0;
        const double size = x_range * w_factor;
        for (int f = 0; pos <= y_range; f++) {
            pos = f * y_step;
            [b moveToPoint:CGPointMake(self.offset_x,
                self.offset_y + pos * h_factor)];
            [b lineToPoint:CGPointMake(self.offset_x + size,
                self.offset_y + pos * h_factor)];
        }
    }

    [self.white_lines_layer setQuartzPath:b];

    // Create axis and daily ticks.
    b = [NSBezierPath new];

    if (x_axis && y_axis) {
        // Axis.
        [b moveToPoint:CGPointMake(self.offset_x + 1, self.offset_y)];
        [b lineToPoint:CGPointMake(self.offset_x + 1,
            self.offset_y + y_range * h_factor)];
        [b moveToPoint:CGPointMake(self.offset_x + 1, self.offset_y)];
        [b lineToPoint:CGPointMake(self.offset_x + x_range * w_factor,
            self.offset_y)];

        // Start going back from the future, at 7 days make longer ticks.
        double pos = x_range * w_factor;
        int count = 0;
        while (pos > 0) {
            [b moveToPoint:CGPointMake(self.offset_x + pos, self.offset_y)];
            if ((count % 7) == 0)
                [b lineToPoint:CGPointMake(self.offset_x + pos,
                    self.offset_y + y_step * h_factor)];
            else
                [b lineToPoint:CGPointMake(self.offset_x + pos,
                    self.offset_y + 0.5 * y_step * h_factor)];
            pos -= w_factor;
            count++;
        }
    }

    [self.black_lines_layer setQuartzPath:b];

    NSDictionary *attributes = @{ NSFontAttributeName:
        [NSFont fontWithName:@"Helvetica-Bold" size:16] };

    NSString *text = (y_axis ? [NSString stringWithFormat:@"%0.1f",
        scale_nice_min(y_axis)] : @"");

    NSRect rect;
    rect.size = [text sizeWithAttributes:attributes];
    rect.origin.x = self.offset_x + self.documentVisibleRect.origin.x;
    rect.origin.y = MAX(0, self.offset_y - rect.size.height);
    [self.min_y_text_layer setFrame:rect];
    [self.min_y_text_layer setString:text];

    text = (y_axis ? [NSString stringWithFormat:@"%0.1f",
        scale_nice_max(y_axis)] : @"");

    rect.size = [text sizeWithAttributes:attributes];
    rect.origin.y = [self visible_h] - rect.size.height -
        MAX(0, self.offset_y - rect.size.height);
    [self.max_y_text_layer setFrame:rect];
    [self.max_y_text_layer setString:text];
}

/** Selects a weight in the table.
 * Pass the weight you want to select or nil to deselect. The weight will be
 * highlighted in the graph.
 */
- (void)select_weight:(TWeight*)weight
{
    const double x = (weight ?
        (date(weight) - self.graph_min_date) * self.graph_w_factor : -1);
    const double y = (weight ? (get_localized_weight(weight) -
        self.graph_min_weight) * self.graph_h_factor + self.offset_y : -1);

    NSBezierPath *w = [NSBezierPath new];
    if (x >= 0) {
        [w moveToPoint:CGPointMake(self.offset_x + x, self.offset_y)];
        [w lineToPoint:CGPointMake(self.offset_x + x,
            self.offset_y + self.graph_total_height)];
    }
    [self.selection_x_layer setQuartzPath:w];

    w = [NSBezierPath new];
    if (y >= 0) {
        [w moveToPoint:CGPointMake(self.offset_x, y)];
        [w lineToPoint:CGPointMake(self.offset_x + self.graph_total_width, y)];
    }
    [self.selection_y_layer setQuartzPath:w];

    [self scroll_to_weight:weight];
}

/** Scrolls the graph to the X position of the specified weight.
 * The scrolling is only done if the position is not already visible. The
 * scrolling tries to center the view, which won't be smooth for the user using
 * the cursor keys, but at least it will be fast.
 */
- (void)scroll_to_weight:(TWeight*)weight
{
    if (!weight)
        return;

    NSClipView *clip = CAST(self.contentView, NSClipView);
    const NSRect doc_rect = [self.documentView frame];
    const NSRect visible_rect = clip.documentVisibleRect;
    //CGFloat x = MIN(doc_rect.size.width - visible_rect.size.width,
    //    (date(weight) - self.graph_min_date) * self.graph_w_factor);
    const CGFloat x = (date(weight) - self.graph_min_date) *
        self.graph_w_factor;
    if (x > visible_rect.origin.x &&
            x < visible_rect.origin.x + visible_rect.size.width) {
        // The point is already visible, get out.
        return;
    }

    // Transform the coordinate into scroll origin.
    CGFloat left = x - visible_rect.size.width / 2.0;
    // Now make sure the point doesn't make the document escape the bounds.

    left = MID(0, left, doc_rect.size.width - visible_rect.size.width);
    [clip scrollToPoint:CGPointMake(left, 0)];
    [self reflectScrolledClipView:clip];
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
    const CGFloat x = v.documentVisibleRect.origin.x + self.offset_x;

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
    [self refresh_graph];
}

/** Invoked when the user plugs in/out the mouse on a laptop.
 * This changes the size of window scrollers, so we need to recalculate the
 * size of our visible area.
 */
- (void)scroller_did_change:(NSNotification*)notification
{
    [self refresh_graph];
}

#pragma mark -
#pragma mark Mouse related methods

// We want to handle clicks at first sight.
- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    return YES;
}

/** Handles clicks on the scroll view.
 * Converts the click to a date, then seaches for the nearest weight, and
 * selects it. The conversion is essentially the reverse of what select_weight:
 * is doing.
 */
- (void)mouseDown:(NSEvent*)event
{
    RASSERT(self.graph_w_factor > 0, @"Ugh, weird graph factor", return);
    const long data_points = get_num_weights();
    if (data_points < 1)
        return;
    if (1 == data_points) {
        TWeight *w = get_last_weight();
        //[self select_weight:get_last_weight()];
        [self.click_delegate did_click_on_weight:w];
        return;
    }

    // Ok, we have to search.
    const NSPoint window_point = [event locationInWindow];
    const NSPoint p = [self convertPoint:window_point fromView:nil];
    const NSRect rect = self.documentVisibleRect;
    const time_t clicked_date = self.graph_min_date +
        ((p.x + rect.origin.x) / self.graph_w_factor);
    DLOG(@"Clicked on date %ld", clicked_date);

    // Start up by getting one of the extreme values and its difference.
    TWeight *closest = get_weight(0);
    time_t date_w = date(closest);
    time_t best = (clicked_date > date_w ?
        clicked_date - date_w : date_w - clicked_date);

    for (int f = 1; f < data_points; f++) {
        TWeight *w = get_weight(f);
        date_w = date(w);
        time_t temp = (clicked_date > date_w ?
            clicked_date - date_w : date_w - clicked_date);
        if (temp > best)
            continue;
        best = temp;
        closest = w;
    }

    //[self select_weight:closest];
    [self.click_delegate did_click_on_weight:closest];
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
