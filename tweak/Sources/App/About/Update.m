// GitHub Releases for Thermia, cached for six hours and shared by the Updates page and launch notice.
#import "Core/SGCore.h"
#import "About.h"

static NSString *const kGitHubURL = @"https://api.github.com/repos/vexitocin/thermia/releases?per_page=20";
NSString *const SGUpdateCheckedNotification = @"spotifyglass.update.checked.notification";

static NSString *const kLatestRelease = @"spotifyglass.update.thermia.latest";
static NSString *const kLastCheck = @"spotifyglass.update.checked.at";
static NSString *const kLastStatus = @"spotifyglass.update.status";
static const NSTimeInterval kCheckInterval = 6 * 60 * 60;

static BOOL sg_running;

@implementation SGUpdateRelease
@end

@implementation SGUpdateChange
@end

// "0.14.1" against "0.15": the numbers position by position, a missing one counting zero.
static BOOL isNewer(NSString *candidate, NSString *current) {
    NSArray<NSString *> *left = [candidate componentsSeparatedByString:@"."];
    NSArray<NSString *> *right = [current componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(left.count, right.count); i++) {
        NSInteger a = i < left.count ? left[i].integerValue : 0;
        NSInteger b = i < right.count ? right[i].integerValue : 0;
        if (a != b) return a > b;
    }
    return NO;
}

static NSString *stringOr(id value, NSString *fallback) {
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

#pragma mark - latest release

SGUpdateRelease *SGUpdateNewestRelease(void) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kLatestRelease];
    NSString *version = stringOr(stored[@"version"], nil);
    if (!version.length) return nil;
    SGUpdateRelease *release = [SGUpdateRelease new];
    release.version = version;
    release.url = stringOr(stored[@"url"], nil);
    release.date = stringOr(stored[@"date"], nil);
    release.changes = [stored[@"changes"] isKindOfClass:NSArray.class] ? stored[@"changes"] : @[];
    return release;
}

NSArray<SGUpdateRelease *> *SGUpdateReleases(void) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kLatestRelease];
    NSArray *items = [stored[@"releases"] isKindOfClass:NSArray.class] ? stored[@"releases"] : (stored[@"version"] ? @[stored] : @[]);
    NSMutableArray<SGUpdateRelease *> *releases = [NSMutableArray array];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class] || ![stringOr(item[@"version"], nil) length]) continue;
        SGUpdateRelease *release = [SGUpdateRelease new];
        release.version = item[@"version"];
        release.url = stringOr(item[@"url"], nil);
        release.date = stringOr(item[@"date"], nil);
        NSMutableArray<SGUpdateChange *> *changes = [NSMutableArray array];
        for (NSDictionary *value in [item[@"changes"] isKindOfClass:NSArray.class] ? item[@"changes"] : @[]) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            SGUpdateChange *change = [SGUpdateChange new];
            change.kind = stringOr(value[@"kind"], @"Changes");
            change.text = stringOr(value[@"text"], nil);
            change.url = stringOr(value[@"url"], release.url);
            if (change.text.length) [changes addObject:change];
        }
        release.changes = changes;
        [releases addObject:release];
    }
    return releases;
}

BOOL SGUpdateIsNewer(NSString *version) {
    return version.length && isNewer(version, @(SG_VERSION));
}

NSString *SGUpdateVersion(void) {
    NSString *version = SGUpdateNewestRelease().version;
    return SGUpdateIsNewer(version) ? version : nil;
}

NSString *SGUpdateStatus(void) {
    if (sg_running) return @"Checking...";
    NSString *status = [NSUserDefaults.standardUserDefaults stringForKey:kLastStatus];
    return status ?: @"Not checked";
}

#pragma mark - the check

static NSArray<NSDictionary *> *changesFromBody(NSString *body, NSString *releaseURL) {
    NSMutableArray<NSDictionary *> *changes = [NSMutableArray array];
    NSString *kind = @"Changes";
    NSRegularExpression *linkPattern = [NSRegularExpression regularExpressionWithPattern:@"\\((https?://[^)]+)\\)" options:0 error:NULL];
    NSRegularExpression *rawURLPattern = [NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s)>]+" options:0 error:NULL];
    NSRegularExpression *markdownLinkPattern = [NSRegularExpression regularExpressionWithPattern:@"\\[([^]]+)\\]\\([^)]+\\)" options:0 error:NULL];
    for (NSString *rawLine in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!line.length) continue;
        if ([line hasPrefix:@"#"]) {
            while ([line hasPrefix:@"#"]) line = [line substringFromIndex:1];
            kind = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!kind.length) kind = @"Changes";
            continue;
        }
        if ([line hasPrefix:@"-"] || [line hasPrefix:@"*"]) line = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        else continue;
        NSTextCheckingResult *link = [linkPattern firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        NSRange urlRange = NSMakeRange(NSNotFound, 0);
        if (link) urlRange = [link rangeAtIndex:1];
        if (!link) {
            link = [rawURLPattern firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
            urlRange = link.range;
        }
        NSString *url = link && urlRange.location != NSNotFound ? [line substringWithRange:urlRange] : releaseURL;
        NSString *text = [markdownLinkPattern stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0, line.length) withTemplate:@"$1"];
        text = [text stringByReplacingOccurrencesOfString:@"`" withString:@""];
        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) [changes addObject:@{@"kind": kind, @"text": text, @"url": url ?: @""}];
    }
    return changes;
}

// Ignore drafts and pre-releases; compare stable tags rather than trusting API ordering.
static NSDictionary *latestReleaseFrom(NSData *data) {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSDictionary *> *releases = [NSMutableArray array];
    for (id item in (NSArray *)json) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *release = item;
        if ([release[@"draft"] boolValue] || [release[@"prerelease"] boolValue]) continue;
        NSString *tag = stringOr(release[@"tag_name"], nil);
        if (!tag.length) continue;
        NSString *version = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
        NSString *url = stringOr(release[@"html_url"], @"");
        NSString *date = stringOr(release[@"published_at"], @"");
        NSArray *changes = changesFromBody(stringOr(release[@"body"], @""), url);
        [releases addObject:@{@"version": version, @"url": url, @"date": date, @"changes": changes}];
    }
    [releases sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        if (isNewer(left[@"version"], right[@"version"])) return NSOrderedAscending;
        if (isNewer(right[@"version"], left[@"version"])) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:releases forKey:@"releases"];
    if (releases.firstObject) [result addEntriesFromDictionary:releases.firstObject];
    return result;
}

static void ask(NSString *url, void (^done)(NSDictionary *release, NSInteger status, NSError *error)) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 10;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    NSURLSessionDataTask *task = [[NSURLSession sessionWithConfiguration:configuration]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
                done(status == 200 ? latestReleaseFrom(data) : nil, status, error);
    }];
    [task resume];
}

void SGCheckForUpdate(BOOL force) {
    if (sg_running) return;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSDate *lastCheck = [store objectForKey:kLastCheck];
    if (!force && lastCheck && -lastCheck.timeIntervalSinceNow < kCheckInterval) return;

    sg_running = YES;
    [store setObject:NSDate.date forKey:kLastCheck];
    [store setObject:@"Checking..." forKey:kLastStatus];
    void (^finish)(NSDictionary *, NSInteger, NSError *) = ^(NSDictionary *release, NSInteger status, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_running = NO;
            if (!release) {
                // Unauthenticated GitHub allows sixty requests an hour per address; a phone behind a
                // carrier NAT can be told to wait, and that is worth reading apart from a dead network.
                SGLog(@"update check failed: HTTP %ld, %@", (long)status,
                      error.localizedDescription ?: @"no release in the reply");
            } else {
                [store setObject:release forKey:kLatestRelease];
                SGLog(@"update check: the newest is %@, this build is %s", release[@"version"] ?: @"none", SG_VERSION);
                [store setObject:SGUpdateVersion() ? [NSString stringWithFormat:@"Thermia %@ is out", SGUpdateVersion()] : @"Up to date" forKey:kLastStatus];
            }
            if (!release) [store setObject:@"Could not check" forKey:kLastStatus];
            [NSNotificationCenter.defaultCenter postNotificationName:SGUpdateCheckedNotification object:nil];
        });
    };
    SGLog(@"update check: asking Thermia GitHub Releases");
    ask(kGitHubURL, finish);
}
