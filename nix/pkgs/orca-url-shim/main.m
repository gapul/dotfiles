// MakerWorld's "Open in Bambu Studio" button opens a bambustudio:// URL. OrcaSlicer can slice and
// print for the A1 mini on its own, but it only claims orcaslicer:// with LaunchServices, so the
// button does nothing once Bambu Studio is gone. This bundle claims the Bambu schemes and hands
// the URL to Orca.
//
// Why not just add the scheme to OrcaSlicer.app/Contents/Info.plist: Orca is signed with a
// hardened runtime, so editing its Info.plist breaks the signature and the app stops launching.
// The edit would also be wiped by every cask upgrade.
//
// Measured quirks of Orca's own URL parser (2.4.2), which this rewrite works around:
//   - it requires the URL to start with "orcaslicer://open?file="
//   - it then reads everything to the end of the string as the download URL, so a trailing
//     "&name=x.3mf" ends up inside the URL and the download 404s
//   - "?name=...&file=..." (file not first) is ignored entirely
// So: pull out the file parameter and pass it with nothing after it.

#import <AppKit/AppKit.h>

static NSString *RewriteURL(NSString *input) {
  NSRange sep = [input rangeOfString:@"://"];
  if (sep.location == NSNotFound) {
    return nil;
  }
  NSString *tail = [input substringFromIndex:NSMaxRange(sep)];
  NSRange q = [tail rangeOfString:@"?"];
  if (q.location == NSNotFound) {
    return [@"orcaslicer://" stringByAppendingString:tail];
  }
  NSString *query = [tail substringFromIndex:NSMaxRange(q)];
  for (NSString *param in [query componentsSeparatedByString:@"&"]) {
    if ([param hasPrefix:@"file="]) {
      return [@"orcaslicer://open?" stringByAppendingString:param];
    }
  }
  // No file parameter: hand it over unchanged rather than dropping it on the floor.
  return [@"orcaslicer://" stringByAppendingString:tail];
}

@interface Shim : NSObject
@end

@implementation Shim
- (void)handleGetURL:(NSAppleEventDescriptor *)event
    withReplyEvent:(NSAppleEventDescriptor *)reply {
  NSString *incoming =
      [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
  NSString *rewritten = RewriteURL(incoming);
  if (rewritten != nil) {
    NSURL *url = [NSURL URLWithString:rewritten];
    if (url != nil) {
      [[NSWorkspace sharedWorkspace] openURL:url];
    }
  }
  // openURL: has handed off to LaunchServices by now, but give it a moment before tearing the
  // process down.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                 dispatch_get_main_queue(), ^{
                   [NSApp terminate:nil];
                 });
}
@end

static int SelfTest(void) {
  NSArray *cases = @[
    @[ @"bambustudio://open?file=http%3A%2F%2Fx%2Fa.3mf&name=a.3mf",
       @"orcaslicer://open?file=http%3A%2F%2Fx%2Fa.3mf" ],
    @[ @"bambustudio://open?name=a.3mf&file=http%3A%2F%2Fx%2Fa.3mf",
       @"orcaslicer://open?file=http%3A%2F%2Fx%2Fa.3mf" ],
    @[ @"bambustudioopen://open?file=http://x/a.3mf&name=a.3mf",
       @"orcaslicer://open?file=http://x/a.3mf" ],
    @[ @"bambustudio://open?file=http%3A%2F%2Fx%2Fa.3mf",
       @"orcaslicer://open?file=http%3A%2F%2Fx%2Fa.3mf" ],
    @[ @"bambustudio://open", @"orcaslicer://open" ],
  ];
  for (NSArray *c in cases) {
    NSString *got = RewriteURL(c[0]);
    if (![got isEqualToString:c[1]]) {
      fprintf(stderr, "FAIL %s -> %s (want %s)\n", [c[0] UTF8String],
              got ? [got UTF8String] : "(nil)", [c[1] UTF8String]);
      return 1;
    }
  }
  if (RewriteURL(@"no-scheme-here") != nil) {
    fprintf(stderr, "FAIL: expected nil for a URL with no scheme\n");
    return 1;
  }
  printf("ok\n");
  return 0;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
      return SelfTest();
    }
    [NSApplication sharedApplication];
    Shim *shim = [[Shim alloc] init];
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:shim
            andSelector:@selector(handleGetURL:withReplyEvent:)
          forEventClass:kInternetEventClass
             andEventID:kAEGetURL];
    // If LaunchServices starts us without ever delivering a URL, do not linger.
    [NSTimer scheduledTimerWithTimeInterval:20.0
                                    repeats:NO
                                      block:^(NSTimer *timer) {
                                        [NSApp terminate:nil];
                                      }];
    [NSApp run];
  }
  return 0;
}
