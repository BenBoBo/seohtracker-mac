#import "EHBannerButton.h"

#import "ELHASO.h"


@interface EHBannerButton ()

/// Adds a tracking area to change the mouse arrow icon.
@property (nonatomic, strong) NSTrackingArea *tracking_area;
@end

@implementation EHBannerButton

- (void)awakeFromNib
{
    [super awakeFromNib];
    DLOG(@"Awaking banner button");
    LASSERT(!self.tracking_area, @"Double call?");
    self.tracking_area = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingCursorUpdate | NSTrackingActiveAlways
        owner: self userInfo:nil];
    [self addTrackingArea:self.tracking_area];
}

/// Detects mouse hovers to change the cursor icon.
- (void)cursorUpdate:(NSEvent *)event
{
    [[NSCursor pointingHandCursor] set];
}

@end
