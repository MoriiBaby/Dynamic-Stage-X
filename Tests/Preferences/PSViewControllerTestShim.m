#import "PSViewControllerTestShim.h"

static NSUInteger ParentLoads;
@implementation PSViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    ParentLoads += 1;
}
@end

@implementation PSListController
- (void)viewDidLoad {
    [super viewDidLoad];
    // Model the failing ownership boundary, not an implementation of Apple's framework:
    // PSListController owns specifier groups; a subclass's foreign data-source count
    // must not be interpreted as group entries in that separate model.
    id<UITableViewDataSource> dataSource = (id)self;
    if ([self respondsToSelector:@selector(numberOfSectionsInTableView:)]) {
        UITableView *internalTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 390, 844)
                                                                style:UITableViewStyleGrouped];
        NSInteger count = [dataSource numberOfSectionsInTableView:internalTable];
        if (count > 0) {
            NSMutableArray *specifierGroups = [NSMutableArray array];
            (void)[specifierGroups objectAtIndex:0];
        }
    }
}
@end

NSString *DXCaptureException(void (^action)(void)) {
    @try { action(); return nil; }
    @catch (NSException *exception) { return exception.name; }
}
NSUInteger DXPreferencesParentLoads(void) { return ParentLoads; }
