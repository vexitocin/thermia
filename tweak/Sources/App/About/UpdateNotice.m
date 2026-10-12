// A release notice is offered once per version, after Spotify's own startup screens have settled.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"

static NSString *const kTold = @"spotifyglass.update.told";
static const NSTimeInterval kSettle = 6;
static const NSTimeInterval kRetry = 4;
static const NSInteger kTries = 15;
static BOOL sg_offered;

static NSArray<SGUpdateChange *> *changesSinceThisBuild(void) {
    NSMutableArray<SGUpdateChange *> *changes = [NSMutableArray array];
    for (SGUpdateRelease *release in SGUpdateReleases()) {
        if (!SGUpdateIsNewer(release.version)) break;
        [changes addObjectsFromArray:release.changes];
    }
    return changes;
}

static NSString *noticeBody(NSString *version) {
    NSArray<SGUpdateChange *> *changes = changesSinceThisBuild();
    NSMutableString *body = [NSMutableString stringWithFormat:@"This build is %@.", @(SG_VERSION)];
    NSUInteger shown = MIN(changes.count, (NSUInteger)3);
    for (NSUInteger index = 0; index < shown; index++) [body appendFormat:@"\n\n- %@", changes[index].text];
    if (changes.count > shown)
        [body appendFormat:@"\n\nand %lu more in %@.", (unsigned long)(changes.count - shown), version];
    return body;
}

static void offerWhenClear(NSInteger tries) {
    if (sg_offered || !SGEnabled(SGKeyUpdateNotice)) return;
    NSString *version = SGUpdateVersion();
    if (!version || [[NSUserDefaults.standardUserDefaults stringForKey:kTold] isEqualToString:version]) return;

    UIViewController *top = SGTopController();
    BOOL modal = top.presentingViewController && top.presentingViewController.presentedViewController == top;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !top ||
        SGOnboardingShowing() || [top isKindOfClass:UIAlertController.class] || modal || top.isBeingPresented) {
        if (tries <= 0) {
            SGLog(@"update notice: the screen stayed busy, %@ waits for Mod Settings", version);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            offerWhenClear(tries - 1);
        });
        return;
    }

    sg_offered = YES;
    [NSUserDefaults.standardUserDefaults setObject:version forKey:kTold];
    SGUpdateRelease *release = SGUpdateNewestRelease();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Thermia %@ is out", version]
                                                                  message:noticeBody(version)
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"What's new" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGShowPage(SGTopController(), SGUpdatePage());
        });
    }]];
    if (release.url.length)
        [sheet addAction:[UIAlertAction actionWithTitle:@"Get it" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SGOpenURL(release.url);
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:sheet animated:YES completion:nil];
    SGLog(@"update notice: offered %@ over %@", version, NSStringFromClass(top.class));
}

void SGWatchForUpdates(void) {
    static BOOL installed;
    if (installed) return;
    installed = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:SGUpdateCheckedNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        offerWhenClear(kTries);
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (SGUpdateVersion()) offerWhenClear(kTries);
            SGCheckForUpdate(NO);
        });
    }];
}