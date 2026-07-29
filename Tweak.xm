#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

static dispatch_source_t _killTimer;
static uint64_t _killDeadline;

static void scheduleKill(uint64_t delaySec) {
    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }

    _killDeadline = dispatch_time(DISPATCH_TIME_NOW, delaySec * NSEC_PER_SEC);
    _killTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    dispatch_source_set_timer(_killTimer, _killDeadline,
        DISPATCH_TIME_FOREVER, 0);

    dispatch_source_set_event_handler(_killTimer, ^{
        kill(getpid(), SIGKILL);
    });

    dispatch_resume(_killTimer);
}

static void cancelKill(void) {
    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }

    if (_killDeadline != 0 && dispatch_time(DISPATCH_TIME_NOW, 0) >= _killDeadline) {
        kill(getpid(), SIGKILL);
    }
    _killDeadline = 0;
}

%ctor {
    __block UIApplicationState state;
    if ([NSThread isMainThread]) {
        state = [UIApplication sharedApplication].applicationState;
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            state = [UIApplication sharedApplication].applicationState;
        });
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    // 后台拉起（push/定位/充电）：30s timer
    if (state != UIApplicationStateActive) {
        scheduleKill(30);
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
            cancelKill();
        }];
        return;
    }

    // 前台启动：切后台 60s timer，回前台补刀检查
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        scheduleKill(60);
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        cancelKill();
    }];
}
