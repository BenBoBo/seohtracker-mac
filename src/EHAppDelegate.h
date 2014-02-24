#import "n_global.h"

@interface EHAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;

@end

NSString *format_date(TWeight *weight);
NSString *format_nsdate(NSDate *date);
