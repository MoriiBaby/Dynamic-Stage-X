#import <UIKit/UIKit.h>
// Intentionally minimal and stable across SDK header sets. Do not additionally import
// a dumped PSListController declaration: differing inherited protocol lists would make
// the Swift controller's explicit data-source conformance vary by SDK.
// The real superclass and its instance layout are supplied by Preferences.framework.
@interface PSListController : UIViewController
@end
