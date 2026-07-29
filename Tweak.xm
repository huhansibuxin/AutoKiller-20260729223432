#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <signal.h>
#import <unistd.h>

static dispatch_source_t _killTimer;
static uint64_t _killDeadline;

static void scheduleKill(void) {
    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }

    _killDeadline = dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC);
    _killTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    dispatch_source_set_timer(_killTimer, _killDeadline,
        DISPATCH_TIME_FOREVER, 0);

    dispatch_source_set_event_handler(_killTimer, ^{
        NSLog(@"[AutoKiller] killing via exit(0)");
        _exit(0);
    });

    dispatch_resume(_killTimer);
    NSLog(@"[AutoKiller] kill scheduled (60s)");
}

static void cancelKill(void) {
    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }

    // 后台队列被挂起时 handler 不会执行，回到前台这里补刀
    if (_killDeadline != 0 && dispatch_time(DISPATCH_TIME_NOW, 0) >= _killDeadline) {
        NSLog(@"[AutoKiller] deadline passed, killing now");
        _exit(0);
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

    // 后台拉起：直接启动 60s 倒计时，并注册前台回调补刀
    if (state != UIApplicationStateActive) {
        _killDeadline = dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC);
        _killTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

        dispatch_source_set_timer(_killTimer, _killDeadline,
            DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(_killTimer, ^{
            NSLog(@"[AutoKiller] background launch, killing via exit(0)");
            _exit(0);
        });
        dispatch_resume(_killTimer);

        [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
            cancelKill();
        }];
        return;
    }

    // 前台启动：注册切换通知
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        scheduleKill();
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        cancelKill();
    }];
}
