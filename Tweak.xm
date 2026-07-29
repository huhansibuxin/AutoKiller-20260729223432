#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

static void _ak_log(NSString *msg) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (!paths.count) return;
    NSString *logPath = [[paths firstObject] stringByAppendingPathComponent:@"autokiller.log"];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
        [NSDateFormatter localizedStringFromDate:[NSDate date]
            dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

static dispatch_source_t _killTimer;
static uint64_t _killDeadline;  // nanoseconds from now

static void scheduleKill(uint64_t delaySec) {
    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }

    _ak_log([NSString stringWithFormat:@"scheduleKill(%llu) called", delaySec]);

    _killDeadline = dispatch_time(DISPATCH_TIME_NOW, delaySec * NSEC_PER_SEC);

    _killTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));

    // start after delaySec, then repeat every 1 second
    // when app resumes from suspension, the next tick immediately checks deadline
    dispatch_source_set_timer(_killTimer,
        _killDeadline,
        1 * NSEC_PER_SEC,
        0);

    dispatch_source_set_event_handler(_killTimer, ^{
        uint64_t now = dispatch_time(DISPATCH_TIME_NOW, 0);
        if (now >= _killDeadline) {
            _ak_log([NSString stringWithFormat:@"deadline reached (+%llus), killing",
                (now - _killDeadline) / NSEC_PER_SEC]);
            kill(getpid(), SIGKILL);
        }
        // else: not yet, wait for next tick
    });

    dispatch_resume(_killTimer);
}

static void cancelKill(void) {
    _ak_log(@"cancelKill called");

    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }

    if (_killDeadline != 0 && dispatch_time(DISPATCH_TIME_NOW, 0) >= _killDeadline) {
        uint64_t over = (dispatch_time(DISPATCH_TIME_NOW, 0) - _killDeadline) / NSEC_PER_SEC;
        _ak_log([NSString stringWithFormat:@"deadline passed on return (+%llus), killing", over]);
        kill(getpid(), SIGKILL);
    }
    _killDeadline = 0;
}

%ctor {
    _ak_log(@"%ctor entered");

    __block UIApplicationState state = UIApplicationStateActive;
    @try {
        if ([NSThread isMainThread]) {
            state = [UIApplication sharedApplication].applicationState;
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                state = [UIApplication sharedApplication].applicationState;
            });
        }
    } @catch (NSException *e) {
        _ak_log([NSString stringWithFormat:@"UIApplication exception: %@", e]);
        return;
    }

    _ak_log([NSString stringWithFormat:@"state=%ld (0=Active 1=Inactive 2=Background)", (long)state]);

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    if (state != UIApplicationStateActive) {
        _ak_log(@"background launch, scheduling 30s kill");
        scheduleKill(30);
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
            _ak_log(@"WillEnterForeground (bg launch path)");
            cancelKill();
        }];
        return;
    }

    _ak_log(@"foreground launch, registering notifications");
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        _ak_log(@"DidEnterBackground");
        scheduleKill(60);
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        _ak_log(@"WillEnterForeground (fg path)");
        cancelKill();
    }];
}
