@interface EHRoot_vc : NSViewController

- (void)import_csv;
- (void)export_csv;
- (void)import_csv_file:(NSURL*)url;

- (IBAction)did_touch_modify_button:(id)sender;
- (IBAction)did_touch_minus_button:(id)sender;
- (IBAction)did_touch_plus_button:(id)sender;
- (IBAction)delete_all_entries:(id)sender;

@end
