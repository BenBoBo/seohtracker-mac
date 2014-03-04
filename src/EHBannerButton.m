#import "EHBannerButton.h"

#import "ELHASO.h"
#import "NSArray+ELHASO.h"


#ifdef DEBUG
#define BANNER_DELAY        3
#else
#define BANNER_DELAY        60
#endif

#define FADE_TIME           1.0


@interface EHBannerButton ()

/// Adds a tracking area to change the mouse arrow icon.
@property (nonatomic, strong) NSTrackingArea *tracking_area;

/// Keeps the next index of the banner to display.
@property (nonatomic, assign) int banner_pos;

/// Images to rotate around.
@property (nonatomic, strong) NSArray *filenames;

@end

@implementation EHBannerButton

#pragma mark -
#pragma mark Life

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

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(switch_banner) object:nil];
}

#pragma mark -
#pragma mark Methods

/// Detects mouse hovers to change the cursor icon.
- (void)cursorUpdate:(NSEvent *)event
{
    [[NSCursor pointingHandCursor] set];
}

/// Sets the images and starts rotating them.
- (void)set_images:(NSArray*)filenames
{
    LASSERT(filenames.count > 0, @"Can't set empty rotations!");
    self.filenames = filenames;
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(switch_banner) object:nil];
    [self switch_banner];
}

/// Sets the visible banner to banner_pos and rotates it.
- (void)switch_banner
{
    BLOCK_UI();
    NSString *filename = [self.filenames get:self.banner_pos];
    if (!filename) {
        filename = self.filenames[0];
        self.banner_pos = 0;
    } else {
        self.banner_pos += 1;
    }

    NSImage *image = [NSImage imageNamed:filename];
    LASSERT(image, @"No banner?");
    [self.overlay setImage:self.image];
    [self setImage:image];

    // Fade out the overlay. I don't understand this at all.
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [self.overlay setAlphaValue:1];
    } completionHandler:^{
        dispatch_async_ui(^{
            [[NSAnimationContext currentContext] setDuration:1];
            [[self.overlay animator] setAlphaValue:0];
        });
    }];

    [self performSelector:@selector(switch_banner) withObject:nil
        afterDelay:BANNER_DELAY];
}

@end
