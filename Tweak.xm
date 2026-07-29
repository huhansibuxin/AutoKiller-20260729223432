#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <signal.h>
#import <unistd.h>

static dispatch_source_t _killTimer;
static uint64_t _killDeadline;
static UIBackgroundTaskIdentifier _bgTask;

static void scheduleKill(uint64_t delaySec) {
    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }

    // 申请后台任务，防止进程在 timer 到期前被挂起
    _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"[AutoKiller] bg task expiring, killing now");
        [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
        _exit(0);
    }];

    _killDeadline = dispatch_time(DISPATCH_TIME_NOW, delaySec * NSEC_PER_SEC);
    _killTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    dispatch_source_set_timer(_killTimer, _killDeadline,
        DISPATCH_TIME_FOREVER, 0);

    dispatch_source_set_event_handler(_killTimer, ^{
        NSLog(@"[AutoKiller] timer fired, killing");
        if (_bgTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
            _bgTask = UIBackgroundTaskInvalid;
        }
        _exit(0);
    });

    dispatch_resume(_killTimer);
    NSLog(@"[AutoKiller] kill scheduled (%llus)", delaySec);
}

static void cancelKill(void) {
    if (_killTimer) {
        dispatch_source_cancel(_killTimer);
        _killTimer = nil;
    }
    if (_bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
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

    // 后台拉起（push/定位/充电）：短 timer + 后台任务保活
    if (state != UIApplicationStateActive) {
        scheduleKill(30);
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
            cancelKill();
        }];
        return;
    }

    // 前台启动：注册切换通知
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        scheduleKill(60);
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        cancelKill();
    }];
}
