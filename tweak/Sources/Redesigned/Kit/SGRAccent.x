// The redesign's accent colour, chosen apart from the native look's: its copy of Native/Appearance/Accent.x.
// Accent colour: Spotify's green, #1ED760, is one token. Its three components occur once in the
// whole binary, and every green the app draws, from the play button to the "Zobrazit vše" links
// and the progress bar, is that token or a state blended from it. So it is swapped where it is
// born, in the UIColor initialiser, and the blends follow. Lottie animations carry their own green
// and are caught at the layer, below. Image assets with green baked in, the logo above all, are
// out of reach.
#import "Core/SGCore.h"
#import "SGRAccent.h"
#import "Settings/SGPageStyle.h"

// The greens the app is known to build from literals: the token, and the older brand green the
// upsell backend still names.
static const uint32_t kGreens[] = {0x1ED760, 0x1DB954};

static NSInteger sg_accent = -1;   // 0xRRGGBB once chosen, read at launch

// The redesign's own green until another is picked; Spotify's is a pick of its own, stored as -1.
static const NSInteger kDefaultAccent = 0x37F200;

static NSArray<NSDictionary *> *themePresets(void) {
    static NSArray<NSDictionary *> *presets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        presets = @[
            @{@"name": @"Spotify green", @"rgb": @(-1)},
            @{@"name": @"Thermia green", @"rgb": @(0x37F200)},
            @{@"name": @"Arctic", @"rgb": @(0x83CEFF)},
            @{@"name": @"Rose", @"rgb": @(0xF65E9D)},
            @{@"name": @"Sunset", @"rgb": @(0xFF814A)},
            @{@"name": @"Apple red", @"rgb": @(0xFA243C)},
            @{@"name": @"SoundCloud orange", @"rgb": @(0xFF5500)},
            @{@"name": @"Tidal teal", @"rgb": @(0x00B4B4)},
            @{@"name": @"Violet", @"rgb": @(0xA77BFF)},
            @{@"name": @"Citrus", @"rgb": @(0xD6E945)},
        ];
    });
    return presets;
}

static NSInteger chosen(void) {
    NSInteger rgb = SGInt(SGRKeyAccent, kDefaultAccent);
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : -1;
}

static void unpack(uint32_t rgb, CGFloat *r, CGFloat *g, CGFloat *b) {
    *r = ((rgb >> 16) & 0xFF) / 255.0;
    *g = ((rgb >> 8) & 0xFF) / 255.0;
    *b = (rgb & 0xFF) / 255.0;
}

UIColor *SGRAccentColor(void) {
    NSInteger rgb = chosen();
    if (rgb < 0) return nil;
    CGFloat r, g, b;
    unpack((uint32_t)rgb, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

NSString *SGRAccentLabel(void) {
    NSInteger rgb = chosen();
    for (NSDictionary *preset in themePresets())
        if ([preset[@"rgb"] integerValue] == rgb) return preset[@"name"];
    return [NSString stringWithFormat:@"#%06lX", (long)rgb];
}

NSUInteger SGRThemeCount(void) {
    return themePresets().count;
}

NSString *SGRThemeNameAtIndex(NSUInteger index) {
    return index < themePresets().count ? themePresets()[index][@"name"] : @"";
}

NSInteger SGRThemeRGBAtIndex(NSUInteger index) {
    return index < themePresets().count ? [themePresets()[index][@"rgb"] integerValue] : NSNotFound;
}

NSInteger SGRThemeSelectedIndex(void) {
    NSInteger rgb = chosen();
    NSArray<NSDictionary *> *presets = themePresets();
    for (NSUInteger index = 0; index < presets.count; index++)
        if ([presets[index][@"rgb"] integerValue] == rgb) return (NSInteger)index;
    return NSNotFound;
}

void SGRSetThemeAtIndex(NSUInteger index) {
    if (index < themePresets().count) SGSetInt(SGRKeyAccent, SGRThemeRGBAtIndex(index));
}

BOOL SGRSetAccentHex(NSString *hex) {
    NSString *value = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if (value.length != 6) return NO;
    NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet];
    if ([value rangeOfCharacterFromSet:nonHex].location != NSNotFound) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned int rgb = 0;
    if (![scanner scanHexInt:&rgb] || !scanner.isAtEnd) return NO;
    SGSetInt(SGRKeyAccent, (NSInteger)rgb);
    return YES;
}

// A darker green than the token comes out as the accent darkened by the same amount, so the two
// keep their relation.
static BOOL swap(CGFloat *r, CGFloat *g, CGFloat *b) {
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) {
        CGFloat gr, gg, gb;
        unpack(kGreens[i], &gr, &gg, &gb);
        if (fabs(*r - gr) > 0.01 || fabs(*g - gg) > 0.01 || fabs(*b - gb) > 0.01) continue;
        CGFloat ar, ag, ab;
        unpack((uint32_t)sg_accent, &ar, &ag, &ab);
        CGFloat factor = MAX(gr, MAX(gg, gb)) / (0xD7 / 255.0);
        *r = MIN(1, ar * factor);
        *g = MIN(1, ag * factor);
        *b = MIN(1, ab * factor);
        return YES;
    }
    return NO;
}

%hook UIColor
- (UIColor *)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
%end

// Lottie draws its animations, the play indicator and the checkmarks among them, from colours
// in the animation file straight onto shape layers, or into colour keyframes, never through
// UIColor. The same swap goes on the CGColor. Layers get set off the main thread too, so the
// copy is made with CoreGraphics alone; NULL when the colour is not one of the greens.
static CGColorRef swappedCopy(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetNumberOfComponents(color) != 4) return NULL;
    const CGFloat *c = CGColorGetComponents(color);
    CGFloat r = c[0], g = c[1], b = c[2];
    if (!swap(&r, &g, &b)) return NULL;
    CGFloat out[] = {r, g, b, c[3]};
    return CGColorCreate(CGColorGetColorSpace(color), out);
}

static id swappedValue(id value) {
    CGColorRef swapped = swappedCopy((__bridge CGColorRef)value);
    if (!swapped) return value;
    id boxed = (__bridge_transfer id)swapped;
    return boxed;
}

%hook CAShapeLayer
- (void)setFillColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
- (void)setStrokeColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CABasicAnimation
- (void)setFromValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
- (void)setToValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
%end

%hook CAKeyframeAnimation
- (void)setValues:(NSArray *)values {
    NSMutableArray *mapped = nil;
    for (NSUInteger i = 0; i < values.count; i++) {
        id swapped = swappedValue(values[i]);
        if (swapped == values[i] && !mapped) continue;
        if (!mapped) mapped = [values mutableCopy];
        mapped[i] = swapped;
    }
    NSArray *used = mapped ?: values;
    %orig(used);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_accent = chosen();
    if (sg_accent >= 0) %init;
}
