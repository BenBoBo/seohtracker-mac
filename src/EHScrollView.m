#import "EHScrollView.h"

@implementation EHScrollView

/// Refreshes the table_view unless overlay_view is set to a hidden view.
- (void)reflectScrolledClipView:(NSClipView *)aClipView
{
    [super reflectScrolledClipView:aClipView];
    if (self.overlay_view) {
        if ([self.overlay_view isHidden] || self.overlay_view.alphaValue <= 0)
            return;
    }

    [self.table_view setNeedsDisplay:YES];
}

@end
