// The redesign's accent colour in place of Spotify's green (SGRAccent.x), chosen apart from the native
// look's and stored under its own key; unset is #37F200, negative keeps Spotify's own green.
#import <UIKit/UIKit.h>

#define SGRKeyAccent @"spotifyglass.redesign.accent"   // 0xRRGGBB

UIColor *SGRAccentColor(void);   // nil while Spotify's own green is kept
NSString *SGRAccentLabel(void);  // the selected theme name, or "#RRGGBB" for a custom colour
NSUInteger SGRThemeCount(void);
NSString *SGRThemeNameAtIndex(NSUInteger index);
NSInteger SGRThemeRGBAtIndex(NSUInteger index);
NSInteger SGRThemeSelectedIndex(void);
void SGRSetThemeAtIndex(NSUInteger index);
BOOL SGRSetAccentHex(NSString *hex);

@class SGModRow;
NSArray<SGModRow *> *SGRAppearanceRows(void);   // the accent colour, for the Appearance card
