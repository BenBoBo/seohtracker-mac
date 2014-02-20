#import <Foundation/Foundation.h>

/** \class NSString
 * Appends some custom helpers to NSString for URL management.
 */
@interface NSString (seohyun)

- (float)locale_float;
- (BOOL)is_valid_weight;
- (char*)cstring;

@end

// vim:tabstop=4 shiftwidth=4 syntax=objc
