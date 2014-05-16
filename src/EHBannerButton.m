#import "EHBannerButton.h"

#import "user_config.h"

#import "AnalyticsHelper.h"
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

/// Keeps the next index of the next banner to display.
@property (nonatomic, assign) int next_pos;

/// The currently shown index.
@property (nonatomic, assign) int current_pos;

/// Images to rotate around.
@property (nonatomic, strong) NSArray *filenames;

/// Directions to open when clicked.
@property (nonatomic, strong) NSArray *urls;

@end

@implementation EHBannerButton

#pragma mark -
#pragma mark Life

- (void)awakeFromNib
{
    [super awakeFromNib];
    DLOG(@"Awaking banner button");
    // Sets the tracking area for mouse cursor change.
    LASSERT(!self.tracking_area, @"Double call?");
    self.tracking_area = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingCursorUpdate | NSTrackingActiveAlways
        owner: self userInfo:nil];
    [self addTrackingArea:self.tracking_area];

    // Hooks ourselves as handlers of clicks.
    [self setTarget:self];
    [self setAction:@selector(click_banner:)];

    // Recovers the previous ad position.
    self.next_pos = get_ad_index();
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

/// Convenience method which sets up all the initial static data.
- (void)start
{
    [self set_images:@[@"ad_banner_0", @"ad_banner_1",
        @"ad_banner_2", @"ad_banner_3", @"ad_banner_4"]];

    [self set_urls:@[
        @"https://itunes.apple.com/app/record-my-gps-position/id405865492?mt=8&ls=1",
        @"https://itunes.apple.com/app/submarine-hunt-lite/id422142576?mt=8&ls=1",
        @"http://www.elhaso.es/",
        @"http://nimrod-lang.org",
        @"https://itunes.apple.com/es/app/seohtracker/id805779021?mt=8&ls=1"]];
    self.current_pos = self.next_pos - 1;
    if (self.current_pos < 0)
        self.current_pos = MAX(0, ((int)self.filenames.count) - 1);

    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(switch_banner) object:nil];
    [self switch_banner];
}

/// Sets the images and starts rotating them.
- (void)set_images:(NSArray*)filenames
{
    LASSERT(filenames.count > 0, @"Can't set empty rotations!");
    self.filenames = filenames;
}

/// Transforms NSString objects into NSURLs.
- (void)set_urls:(NSArray*)urls
{
    NSMutableArray *final = [urls get_holder];
    for (id o in urls) {
        NSString *provisional = CAST(o, NSString);
        if (provisional.length < 1) continue;
        NSURL *url = [NSURL URLWithString:provisional];
        if (url) [final addObject:url];
    }

    LASSERT(final.count > 0, @"Can't set empty urls!");
    DLOG(@"Setting urls to %@", final);
    self.urls = final;
}

/// Sets the visible banner to next_pos and rotates it.
- (void)switch_banner
{
    BLOCK_UI();
    NSString *filename = [self.filenames get:self.next_pos];
    if (!filename) {
        filename = self.filenames[0];
        self.current_pos = 0;
        self.next_pos = 1;
    } else {
        self.current_pos = self.next_pos;
        self.next_pos += 1;
        if (self.next_pos >= self.filenames.count)
            self.next_pos = 0;
        set_ad_index(self.next_pos);
    }

    NSImage *image = [NSImage imageNamed:filename];
    LASSERT(image, @"No banner?");
    [image setSize:self.overlay.bounds.size];
    [self.overlay setImage:self.image];
    [self setImage:image];
    //DLOG(@"Showing banner pos %d", self.current_pos);

    // Fade out the overlay. I don't understand this at all.
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [self.overlay setAlphaValue:1];
    } completionHandler:^{
        dispatch_async_ui(^{
            [[NSAnimationContext currentContext] setDuration:FADE_TIME];
            [[self.overlay animator] setAlphaValue:0];
        });
    }];

    [self performSelector:@selector(switch_banner) withObject:nil
        afterDelay:BANNER_DELAY];
}

/// Handles clicks on the banner.
- (void)click_banner:(id)sender
{
    NSURL *url = CAST([self.urls get:self.current_pos], NSURL);
    DLOG(@"Clicked on %@", url);
    [AnalyticsHelper.sharedInstance recordCachedEventWithCategory:@"Ads"
        action:@"Clicked banner" label:[url absoluteString]
        value:@(self.current_pos)];
    if (url)
        [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
