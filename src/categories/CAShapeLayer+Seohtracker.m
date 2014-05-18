#import "CAShapeLayer+Seohtracker.h"

#import "NSBezierPath+Seohtracker.h"

#import <QuartzCore/QuartzCore.h>

@implementation CAShapeLayer (Seohtracker)

/** Handy wrapper around NSBezierPath category to avoid manual releases.
 */
- (void)setQuartzPath:(NSBezierPath*)path
{
	if (!path) {
		[self setPath:nil];
		return;
	}
	CGPathRef temp = [path newQuartzPath];
	[self setPath:temp];
	CGPathRelease(temp);
}

@end
