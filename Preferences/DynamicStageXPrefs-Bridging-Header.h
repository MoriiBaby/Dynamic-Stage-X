#import <UIKit/UIKit.h>
// Only the Preferences navigation container, not its specifier/table owner.
// The runtime class and its layout are supplied by Preferences.framework.
// Our UIKit child owns all UITableViewDataSource/Delegate selectors.
@interface PSViewController : UIViewController
@end
