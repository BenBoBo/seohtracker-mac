#import "EHSettings_vc.h"

@interface EHSettings_vc ()

@end

@implementation EHSettings_vc

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

#pragma mark -
#pragma mark - RHPreferencesViewControllerProtocol

-(NSString*)identifier
{
    return NSStringFromClass(self.class);
}

-(NSImage*)toolbarItemImage
{
    return [NSImage imageNamed:NSImageNameActionTemplate];
}

-(NSString*)toolbarItemLabel
{
    return @"Settings";
}

-(NSView*)initialKeyView
{
    return nil;
}

@end
