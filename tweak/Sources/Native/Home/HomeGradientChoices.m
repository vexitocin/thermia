// What the Gradient page offers and what the hooks read back, one entry per setting: the names, the
// key it is stored under and the index it falls back to. HomeGradient.x carries the numbers behind
// the names, in the same order as the names themselves.
#import "Core/SGCore.h"
#import "Home.h"

static NSDictionary *choiceDef(SGHomeChoice choice) {
    static NSDictionary<NSNumber *, NSDictionary *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            // A handful of music-service accents beside Spotify green, keeping the same depth and
            // saturation so each sits behind white text the way the green does.
            @(SGHomeChoiceTint): @{
                @"key": @"spotifyglass.homeGradientTint",
                @"default": @0,
                @"names": @[@"Spotify green", @"Apple Music red", @"SoundCloud orange",
                            @"YouTube red", @"Deezer pink", @"Tidal green",
                            @"Amazon Music orange", @"Blue"],
            },
            @(SGHomeChoiceStrength): @{
                @"key": @"spotifyglass.homeGradientStrength",
                @"default": @1,
                @"names": @[@"Subtle", @"Medium", @"Bold"],
            },
            @(SGHomeChoiceHeight): @{
                @"key": @"spotifyglass.homeGradientHeight",
                @"default": @1,
                @"names": @[@"Short", @"Medium", @"Tall", @"The whole screen"],
            },
        };
    });
    return table[@(choice)] ?: table[@(SGHomeChoiceTint)];
}

NSArray<NSString *> *SGHomeChoiceNames(SGHomeChoice choice) {
    return choiceDef(choice)[@"names"];
}

NSString *SGHomeChoiceKey(SGHomeChoice choice) {
    return choiceDef(choice)[@"key"];
}

NSInteger SGHomeChoiceDefault(SGHomeChoice choice) {
    return [choiceDef(choice)[@"default"] integerValue];
}

NSInteger SGHomeChoiceValue(SGHomeChoice choice) {
    NSDictionary *def = choiceDef(choice);
    NSInteger fallback = [def[@"default"] integerValue];
    NSInteger index = SGInt(def[@"key"], fallback);
    return index >= 0 && index < (NSInteger)[def[@"names"] count] ? index : fallback;
}
