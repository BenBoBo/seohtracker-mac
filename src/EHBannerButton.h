/** Special button with rotating banners as hyperlinks.
 *
 * Because mac desktop apps don't have ads.
 */
@interface EHBannerButton : NSButton

- (void)set_images:(NSArray*)filenames;

@end
