#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"
#import "SGRTokens.h"

static UIColor *themeColor(NSInteger rgb) {
    if (rgb < 0) return [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static UIImage *swatchImage(UIColor *color) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28, 28)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect circle = CGRectMake(2, 2, 24, 24);
        [color setFill];
        [[UIBezierPath bezierPathWithOvalInRect:circle] fill];
        [[UIColor colorWithWhite:1 alpha:0.24] setStroke];
        UIBezierPath *outline = [UIBezierPath bezierPathWithOvalInRect:circle];
        outline.lineWidth = 1;
        [outline stroke];
    }];
}

@interface SGRThemePage : SGPage
@end

@implementation SGRThemePage

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Themes";
    return self;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)SGRThemeCount() + 1;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"theme");
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (path.row < (NSInteger)SGRThemeCount()) {
        NSUInteger index = (NSUInteger)path.row;
        NSInteger rgb = SGRThemeRGBAtIndex(index);
        NSString *detail = rgb < 0 ? @"Original Spotify accent" : [NSString stringWithFormat:@"#%06lX", (long)rgb];
        SGFillCell(cell, SGRThemeNameAtIndex(index), detail, nil, nil);
        UIListContentConfiguration *content = [(UIListContentConfiguration *)cell.contentConfiguration copy];
        content.image = swatchImage(themeColor(rgb));
        content.imageProperties.maximumSize = CGSizeMake(28, 28);
        content.imageProperties.reservedLayoutSize = CGSizeMake(28, 28);
        content.imageToTextPadding = 14;
        cell.contentConfiguration = content;
        if (SGRThemeSelectedIndex() == (NSInteger)index) cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        SGFillCell(cell, @"Custom colour", @"Choose any accent colour", nil, nil);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.row == (NSInteger)SGRThemeCount()) {
        SGRPickAccent();
        return;
    }
    SGRSetThemeAtIndex((NSUInteger)path.row);
    [self.tableView reloadData];
}

@end

// The redesign's appearance choices. The page background stays AMOLED black; themes change its accent.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    SGModRow *theme = SGPageRow(@"Theme", ^UIViewController *{ return [SGRThemePage new]; });
    theme.value = ^NSString *{ return SGRAccentLabel(); };
    SGModRow *typeface = SGChoiceRow(@"Typeface", @"Restart Spotify to apply", SGRKeyTypeface, SGRTypefaceNames(), 0);
    return @[
        SGWithSymbol(theme, @"paintpalette"),
        SGWithSymbol(typeface, @"textformat"),
    ];
}
