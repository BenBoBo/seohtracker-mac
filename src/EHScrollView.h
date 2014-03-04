/** Overloads scrolling to refresh table and overlays.
 *
 * See http://stackoverflow.com/a/22172400/172690.
 */
@interface EHScrollView : NSScrollView

/// The base object that will be sent the refresh message.
@property (nonatomic, weak) NSView *table_view;

/// The overlay. If the overlay is hidden or alpha <= 0, no refresh is sent.
@property (nonatomic, weak) NSView *overlay_view;

@end
