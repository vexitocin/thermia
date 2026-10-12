// The Updates page reads the release cache; GitHub is contacted only when the six-hour window allows it.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "About.h"

@interface SGUpdateRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *(^value)(void);
@property (nonatomic, copy) void (^action)(void);
@end

@interface SGUpdateGroup : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *footer;
@property (nonatomic, copy) NSArray<SGUpdateRow *> *rows;
@end

@implementation SGUpdateRow
@end

@implementation SGUpdateGroup
@end

static SGUpdateRow *linkRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *url) {
    SGUpdateRow *row = [SGUpdateRow new];
    row.title = title;
    row.subtitle = subtitle;
    row.symbol = symbol;
    row.action = ^{ SGOpenURL(url); };
    return row;
}

static SGUpdateGroup *group(NSString *title, NSArray<SGUpdateRow *> *rows) {
    SGUpdateGroup *section = [SGUpdateGroup new];
    section.title = title;
    section.rows = rows;
    return section;
}

static NSString *dateInWords(NSString *published, NSString *format) {
    static NSISO8601DateFormatter *reader;
    static NSDateFormatter *writer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reader = [NSISO8601DateFormatter new];
        writer = [NSDateFormatter new];
        writer.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSDate *date = published.length ? [reader dateFromString:published] : nil;
    if (!date) return @"";
    writer.dateFormat = format;
    return [writer stringFromDate:date];
}

static NSString *shortDate(NSString *published) { return dateInWords(published, @"d MMM yyyy"); }
static NSString *longDate(NSString *published) { return dateInWords(published, @"d MMMM yyyy"); }

@interface SGUpdatePageController : SGPage
@end

@implementation SGUpdatePageController {
    NSArray<SGUpdateGroup *> *_groups;
    UIView *_intro;
    NSTimer *_ticker;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Updates";
    _groups = [self build];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(checkLanded)
                                               name:SGUpdateCheckedNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_ticker invalidate];
}

static NSArray<SGUpdateRelease *> *releasesToShow(void) {
    NSArray<SGUpdateRelease *> *releases = SGUpdateReleases();
    NSMutableArray<SGUpdateRelease *> *shown = [NSMutableArray array];
    for (SGUpdateRelease *release in releases) {
        if (!SGUpdateIsNewer(release.version)) break;
        [shown addObject:release];
    }
    if (!shown.count && releases.firstObject) [shown addObject:releases.firstObject];
    return shown;
}

- (NSString *)introText {
    SGUpdateRelease *newest = SGUpdateNewestRelease();
    if (!newest) return [NSString stringWithFormat:@"This build is %@. %@.", @(SG_VERSION), SGUpdateStatus()];
    NSString *date = longDate(newest.date);
    NSString *when = date.length ? [@" came out on " stringByAppendingString:date] : @" is out";
    if (SGUpdateVersion())
        return [NSString stringWithFormat:@"%@%@, and this build is %@. Everything in between is below.",
                newest.version, when, @(SG_VERSION)];
    return [NSString stringWithFormat:@"This build, %@, is Thermia's newest release; it%@. What went into it is below.",
            @(SG_VERSION), when];
}

- (NSArray<SGUpdateGroup *> *)build {
    NSMutableArray<SGUpdateGroup *> *groups = [NSMutableArray array];
    SGUpdateRow *check = [SGUpdateRow new];
    check.title = @"Check now";
    check.symbol = @"arrow.clockwise";
    check.value = ^NSString *{ return SGUpdateStatus(); };
    check.action = ^{ SGCheckForUpdate(YES); };
    NSMutableArray<SGUpdateRow *> *top = [NSMutableArray arrayWithObject:check];
    SGUpdateRelease *newest = SGUpdateNewestRelease();
    if (SGUpdateVersion() && newest.url.length)
        [top addObject:linkRow([@"Get " stringByAppendingString:newest.version],
                               @"The release on GitHub, where its .deb is", @"arrow.down.circle", newest.url)];
    [top addObject:linkRow(@"All releases", @"Every Thermia version", @"clock.arrow.circlepath",
                           [SGRepoURL stringByAppendingString:@"/releases"])];
    [groups addObject:group(nil, top)];

    SGUpdateRow *notice = [SGUpdateRow new];
    notice.title = @"Tell me when one is out";
    notice.symbol = @"bell";
    notice.key = SGKeyUpdateNotice;
    [groups addObject:group(nil, @[notice])];

    for (SGUpdateRelease *release in releasesToShow()) {
        NSMutableArray<NSString *> *kinds = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSMutableArray<SGUpdateRow *> *> *byKind = [NSMutableDictionary dictionary];
        for (SGUpdateChange *change in release.changes) {
            NSMutableArray<SGUpdateRow *> *rows = byKind[change.kind];
            if (!rows) {
                rows = [NSMutableArray array];
                byKind[change.kind] = rows;
                [kinds addObject:change.kind];
            }
            SGUpdateRow *row = [SGUpdateRow new];
            row.title = change.text;
            if (change.url.length) row.action = ^{ SGOpenURL(change.url); };
            [rows addObject:row];
        }
        NSString *date = shortDate(release.date);
        if (!kinds.count) {
            SGUpdateRow *empty = [SGUpdateRow new];
            empty.title = @"Nothing written down";
            empty.subtitle = release.url.length ? @"Tap to read the release on GitHub" : nil;
            if (release.url.length) empty.action = ^{ SGOpenURL(release.url); };
            [groups addObject:group([NSString stringWithFormat:@"%@%@", release.version,
                                     date.length ? [@" · " stringByAppendingString:date] : @""], @[empty])];
            continue;
        }
        [kinds enumerateObjectsUsingBlock:^(NSString *kind, NSUInteger index, BOOL *stop) {
            NSString *title = [NSString stringWithFormat:@"%@ · %@%@", release.version, kind,
                               index == 0 && date.length ? [@" · " stringByAppendingString:date] : @""];
            [groups addObject:group(title, byKind[kind])];
        }];
    }
    return groups;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _intro = SGNote([self introText]);
    self.tableView.tableHeaderView = _intro;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _intro, 24, 0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [_ticker invalidate];
    _ticker = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(readStatus) userInfo:nil repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_ticker invalidate];
    _ticker = nil;
}

- (void)readStatus {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        SGUpdateRow *row = [self rowAt:[self.tableView indexPathForCell:cell]];
        UILabel *label = (UILabel *)cell.accessoryView;
        if (!row.value || ![label isKindOfClass:UILabel.class]) continue;
        label.text = row.value();
        [label sizeToFit];
        [cell setNeedsLayout];
    }
}

- (void)checkLanded {
    _groups = [self build];
    UILabel *note = (UILabel *)_intro.subviews.firstObject;
    note.text = [self introText];
    [self.view setNeedsLayout];
    [UIView transitionWithView:self.tableView duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ [self.tableView reloadData]; } completion:nil];
}

- (SGUpdateRow *)rowAt:(NSIndexPath *)path {
    if (!path || path.section >= (NSInteger)_groups.count) return nil;
    NSArray *rows = _groups[(NSUInteger)path.section].rows;
    return path.row < (NSInteger)rows.count ? rows[(NSUInteger)path.row] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return (NSInteger)_groups.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_groups[(NSUInteger)section].rows.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = _groups[(NSUInteger)section].title;
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return _groups[(NSUInteger)section].title ? SGSectionHeaderHeight : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    NSString *footer = _groups[(NSUInteger)section].footer;
    return footer ? SGSectionFooter(table, footer) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    NSString *footer = _groups[(NSUInteger)section].footer;
    return footer ? SGSectionFooterHeight(table, footer) : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGUpdateRow *row = [self rowAt:path];
    UITableViewCell *cell = SGDequeueCell(table, row.symbol ? @"tiled" : @"line");
    cell.accessoryView = nil;
    SGFillCell(cell, row.title, row.subtitle, nil, nil);
    if (row.symbol) {
        UIListContentConfiguration *content = [(UIListContentConfiguration *)cell.contentConfiguration copy];
        content.image = SGTileImage(row.symbol);
        content.imageToTextPadding = 14;
        cell.contentConfiguration = content;
    }
    cell.separatorInset = UIEdgeInsetsMake(0, row.symbol ? 58 : 16, 0, 0);
    if (row.key) {
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = SGGreen();
        toggle.on = SGEnabled(row.key);
        toggle.accessibilityLabel = row.title;
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (row.value) {
        UILabel *label = [UILabel new];
        label.font = SGTitleFont();
        label.textColor = SGGrey();
        label.text = row.value();
        [label sizeToFit];
        cell.accessoryView = label;
    }
    cell.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.accessibilityTraits = row.action ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    return cell;
}

- (void)toggled:(UISwitch *)toggle {
    UIView *view = toggle;
    while (view && ![view isKindOfClass:UITableViewCell.class]) view = view.superview;
    SGUpdateRow *row = [self rowAt:[self.tableView indexPathForCell:(UITableViewCell *)view]];
    if (row.key) SGSetEnabled(row.key, toggle.on);
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return [self rowAt:path].action != nil;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGUpdateRow *row = [self rowAt:path];
    if (row.action) row.action();
    if (row.value) [self readStatus];
}

@end

UIViewController *SGUpdatePage(void) {
    SGCheckForUpdate(NO);
    return [SGUpdatePageController new];
}