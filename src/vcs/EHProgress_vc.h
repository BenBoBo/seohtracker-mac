@interface EHProgress_vc : NSWindowController

+ (EHProgress_vc*)start_in:(NSViewController*)parent_vc;
- (void)dismiss;

@end
