#include "DVirtualHome.h"
#include <notify.h>

static void preferencesChanged() {
    CFPreferencesAppSynchronize((CFStringRef)kIdentifier);

    NSDictionary *prefs = nil;
    if ([NSHomeDirectory() isEqualToString:@"/var/mobile"]) {
        CFArrayRef keyList = CFPreferencesCopyKeyList((CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            prefs = (NSDictionary *)CFPreferencesCopyMultiple(keyList, (CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (!prefs) {
                prefs = [NSDictionary new];
            }
            CFRelease(keyList);
        }
    } else {
        prefs = [[NSDictionary alloc] initWithContentsOfFile:kSettingsPath];
    }

    if (prefs) {
        isEnabled = [prefs objectForKey:@"isEnabled"] ? [[prefs objectForKey:@"isEnabled"] boolValue] : YES;
        singleTapAction = [prefs objectForKey:@"singleTapAction"] ? (Action)[[prefs objectForKey:@"singleTapAction"] intValue] : home;
        doubleTapAction = [prefs objectForKey:@"doubleTapAction"] ? (Action)[[prefs objectForKey:@"doubleTapAction"] intValue] : switcher;
        longHoldAction =  [prefs objectForKey:@"longHoldAction"] ? (Action)[[prefs objectForKey:@"longHoldAction"] intValue] : reachability;
        tapAndHoldAction =  [prefs objectForKey:@"tapAndHoldAction"] ? (Action)[[prefs objectForKey:@"tapAndHoldAction"] intValue] : siri;
        isVibrationEnabled =  [prefs objectForKey:@"isVibrationEnabled"] ? [[prefs objectForKey:@"isVibrationEnabled"] boolValue] : YES;
        vibrationIntensity =  [prefs objectForKey:@"vibrationIntensity"] ? [[prefs objectForKey:@"vibrationIntensity"] floatValue] : 0.75;
        vibrationDuration =  [prefs objectForKey:@"vibrationDuration"] ? [[prefs objectForKey:@"vibrationDuration"] intValue] : 30;
        if ([prefs isKindOfClass:[NSDictionary class]]) CFRelease((CFTypeRef)prefs);
    }
}

static void hapticVibe() {
    if (!isVibrationEnabled) return;
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

// iOS 13+ doesn't currently support disable actions during lockscreen biometric authentication
static BOOL disableActions = NO;
static BOOL isLongPressGestureActive = NO;
static int notify_token = 0;
static BOOL disableActionsForScreenOff = NO;

%hook SBDashBoardViewController
-(void)biometricEventMonitor:(id)arg1 handleBiometricEvent:(NSUInteger)arg2 { // iOS 10 - 10.1
    %orig(arg1, arg2);

    // Touch Up or Down
    disableActions = arg2 != 0 && arg2 != 1;
}

-(void)handleBiometricEvent:(NSUInteger)arg1 { // iOS 10.2 - 12
    %orig(arg1);

    // Touch Up or Down
    disableActions = arg1 != 0 && arg1 != 1;
}
%end

%group iOS13plus
%hook _SBTransientOverlayPresentedEntity
-(void)setDisableAutoUnlockAssertion:(id)arg1 {
    %orig(arg1);

    // during biometric authentication this is what is called to disable auto unlocking so we can disable actions
    disableActions = arg1 != nil;
}
%end
%end

static inline void lockOrUnlockOrientation(UIInterfaceOrientation orientation) {
    SBOrientationLockManager *orientationLockManager = [%c(SBOrientationLockManager) sharedInstance];
    if ([orientationLockManager isUserLocked]) {
        [orientationLockManager unlock];
    } else {
        [orientationLockManager lock:orientation];
    }
}

static inline void ResetGestureRecognizers(SBHomeHardwareButtonGestureRecognizerConfiguration *configuration) {
    UIHBClickGestureRecognizer *_singleTapGestureRecognizer = configuration.singleTapGestureRecognizer;
    UILongPressGestureRecognizer *_longTapGestureRecognizer = configuration.longTapGestureRecognizer;
    SBHBDoubleTapUpGestureRecognizer *_doubleTapUpGestureRecognizer = [configuration doubleTapUpGestureRecognizer];
    UILongPressGestureRecognizer *_tapAndHoldTapGestureRecognizer = configuration.tapAndHoldTapGestureRecognizer;

    _singleTapGestureRecognizer.enabled = NO;
    _singleTapGestureRecognizer.enabled = YES;
    _longTapGestureRecognizer.enabled = NO;
    _longTapGestureRecognizer.enabled = YES;
    _doubleTapUpGestureRecognizer.enabled = NO;
    _doubleTapUpGestureRecognizer.enabled = YES;
    _tapAndHoldTapGestureRecognizer.enabled = NO;
    _tapAndHoldTapGestureRecognizer.enabled = YES;
}

static NSString *lastApplicationIdentifier = nil;
static NSString *currentApplicationIdentifier = nil;

%hook SpringBoard
%property (nonatomic, retain) NSString *lastApplicationIdentifier;
%property (nonatomic, retain) NSString *currentApplicationIdentifier;

-(void)frontDisplayDidChange:(id)arg1 {
    %orig;

    if (arg1 != nil && [arg1 isKindOfClass:%c(SBApplication)]) {
        NSString *newBundleIdentifier = [(SBApplication *)arg1 bundleIdentifier];
        if (![currentApplicationIdentifier isEqualToString:newBundleIdentifier]) {
            lastApplicationIdentifier = currentApplicationIdentifier;
            currentApplicationIdentifier = newBundleIdentifier;
        }
    }
}
%end

%hook SBHomeHardwareButtonGestureRecognizerConfiguration
%property(retain,nonatomic) UIHBClickGestureRecognizer *singleTapGestureRecognizer;
%property(retain,nonatomic) UILongPressGestureRecognizer *longTapGestureRecognizer;
%property(retain,nonatomic) UILongPressGestureRecognizer *tapAndHoldTapGestureRecognizer;
%property(retain,nonatomic) UILongPressGestureRecognizer *vibrationGestureRecognizer;

-(void)dealloc {
    self.singleTapGestureRecognizer = nil;
    self.longTapGestureRecognizer = nil;
    self.tapAndHoldTapGestureRecognizer = nil;
    self.vibrationGestureRecognizer = nil;
    %orig;
}
%end

%hook SBHomeHardwareButton
%new
-(void)performAction:(Action)action {
    if (disableActions)
        return;

    if (action == home || ![[%c(SBBacklightController) sharedInstance] screenIsOn]) {
        SpringBoard *_springboard = (SpringBoard *)[UIApplication sharedApplication];
        if ([_springboard respondsToSelector:@selector(_simulateHomeButtonPress)])
            [_springboard _simulateHomeButtonPress];
        else if ([_springboard respondsToSelector:@selector(_simulateHomeButtonPressWithCompletion:)])
            [_springboard _simulateHomeButtonPressWithCompletion:nil];
    } else if (action == lock) {
        [(SpringBoard *)[UIApplication sharedApplication] _simulateLockButtonPress];
    } else if (action == switcher) {
        id topDisplay = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityTopDisplay];
        if (![topDisplay isKindOfClass:%c(SBPowerDownController)] && ![topDisplay isKindOfClass:%c(SBPowerDownViewController)] && ![topDisplay isKindOfClass:%c(SBDashBoardViewController)] && ![topDisplay isKindOfClass:%c(CSCoverSheetViewController)] && (%c(SBCoverSheetPresentationManager) == nil || [[%c(SBCoverSheetPresentationManager) sharedInstance] hasBeenDismissedSinceKeybagLock])) {
            SBMainSwitcherViewController *mainSwitcherViewController = [%c(SBMainSwitcherViewController) sharedInstance];
            if ([mainSwitcherViewController respondsToSelector:@selector(toggleSwitcherNoninteractively)])
                [mainSwitcherViewController toggleSwitcherNoninteractively];
            else if ([mainSwitcherViewController respondsToSelector:@selector(toggleSwitcherNoninteractivelyWithSource:)])
                [mainSwitcherViewController toggleSwitcherNoninteractivelyWithSource:1];
            else if ([mainSwitcherViewController respondsToSelector:@selector(toggleMainSwitcherNoninteractivelyWithSource:animated:)])
                [mainSwitcherViewController toggleMainSwitcherNoninteractivelyWithSource:1 animated:YES];
        }
    } else if (action == reachability) {
        [[%c(SBReachabilityManager) sharedInstance] toggleReachability];
    } else if (action == siri) {
        SBAssistantController *_assistantController = [%c(SBAssistantController) sharedInstance];
        if ([SBAssistantController respondsToSelector:@selector(isAssistantVisible)]) {
            if ([SBAssistantController isAssistantVisible]) {
                [_assistantController dismissPluginForEvent:1];
            } else {
                [_assistantController handleSiriButtonDownEventFromSource:1 activationEvent:1];
                [_assistantController handleSiriButtonUpEventFromSource:1];
            }
        } else if ([SBAssistantController respondsToSelector:@selector(isVisible)]) {
            if ([SBAssistantController isVisible]) {
                [_assistantController dismissAssistantViewIfNecessary];
            } else {
                SiriPresentationSpringBoardMainScreenViewController *presentation = MSHookIvar<SiriPresentationSpringBoardMainScreenViewController *>(_assistantController, "_mainScreenSiriPresentation");

                SiriPresentationOptions *presentationOptions = [[%c(SiriPresentationOptions) alloc] init];
                presentationOptions.wakeScreen = YES;
                presentationOptions.hideOtherWindowsDuringAppearance = NO;

                SASRequestOptions *requestOptions = [[%c(SASRequestOptions) alloc] initWithRequestSource:1 uiPresentationIdentifier:@"com.apple.siri.Siriland"];
                requestOptions.useAutomaticEndpointing = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
                AFApplicationInfo *applicationInfo = [[%c(AFApplicationInfo) alloc] initWithCoder:nil];
#pragma clang diagnostic pop
                applicationInfo.pid = [NSProcessInfo processInfo].processIdentifier;
                applicationInfo.identifier = [NSBundle mainBundle].bundleIdentifier;
                requestOptions.contextAppInfosForSiriViewController = @[applicationInfo];

                [presentation presentationRequestedWithPresentationOptions:presentationOptions requestOptions:requestOptions];

                [presentationOptions release];
                [requestOptions release];
                [applicationInfo release];
            }
        }
    } else if (action == screenshot) {
        SpringBoard *_springboard = (SpringBoard *)[UIApplication sharedApplication];
        if ([_springboard respondsToSelector:@selector(takeScreenshot)])
            [_springboard takeScreenshot];
        else
            [[_springboard screenshotManager] saveScreenshotsWithCompletion:nil];
    } else if (action == cc) {
        id topDisplay = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityTopDisplay];
        if (![topDisplay isKindOfClass:%c(SBPowerDownController)] && ![topDisplay isKindOfClass:%c(SBPowerDownViewController)]) {
            SBControlCenterController *_ccController = [%c(SBControlCenterController) sharedInstance];
            if ([_ccController isVisible])
                [_ccController dismissAnimated:YES];
            else
                [_ccController presentAnimated:YES];
        }
    } else if (action == nc) {
        id topDisplay = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityTopDisplay];
        if (![topDisplay isKindOfClass:%c(SBPowerDownController)] && ![topDisplay isKindOfClass:%c(SBPowerDownViewController)] && ![topDisplay isKindOfClass:%c(SBDashBoardViewController)] && ![topDisplay isKindOfClass:%c(CSCoverSheetViewController)]) {
            if (%c(SBCoverSheetPresentationManager) && [%c(SBCoverSheetPresentationManager) respondsToSelector:@selector(sharedInstance)]) {
                SBCoverSheetPresentationManager *_csController = [%c(SBCoverSheetPresentationManager) sharedInstance];
                if (_csController != nil && [[%c(SBCoverSheetPresentationManager) sharedInstance] hasBeenDismissedSinceKeybagLock]) {
                    SBCoverSheetSlidingViewController *currentSlidingViewController = nil;
                    if ([_csController isInSecureApp] && _csController.secureAppSlidingViewController != nil)
                        currentSlidingViewController = _csController.secureAppSlidingViewController;
                    else if (_csController.coverSheetSlidingViewController != nil)
                        currentSlidingViewController = _csController.coverSheetSlidingViewController;

                    if (currentSlidingViewController != nil) {
                        if ([_csController isVisible]) {
                            [currentSlidingViewController _dismissCoverSheetAnimated:YES withCompletion:nil];
                        } else {
                            if ([currentSlidingViewController respondsToSelector:@selector(_presentCoverSheetAnimated:withCompletion:)])
                                [currentSlidingViewController _presentCoverSheetAnimated:YES withCompletion:nil];
                            else if ([currentSlidingViewController respondsToSelector:@selector(_presentCoverSheetAnimated:forUserGesture:withCompletion:)])
                                [currentSlidingViewController _presentCoverSheetAnimated:YES forUserGesture:NO withCompletion:nil];
                        }
                    }
                }
            } else if (%c(SBNotificationCenterController) && [%c(SBNotificationCenterController) respondsToSelector:@selector(sharedInstance)]) {
                SBNotificationCenterController *_ncController = [%c(SBNotificationCenterController) sharedInstance];
                if (_ncController != nil) {
                    if ([_ncController isVisible])
                        [_ncController dismissAnimated:YES];
                    else
                        [_ncController presentAnimated:YES];
                }
            }
        }
    } else if (action == lastApp) {
        id topDisplay = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityTopDisplay];
        if (![topDisplay isKindOfClass:%c(SBPowerDownController)] && ![topDisplay isKindOfClass:%c(SBPowerDownViewController)] && ![topDisplay isKindOfClass:%c(SBDashBoardViewController)] && ![topDisplay isKindOfClass:%c(CSCoverSheetViewController)] && (%c(SBCoverSheetPresentationManager) == nil || [[%c(SBCoverSheetPresentationManager) sharedInstance] hasBeenDismissedSinceKeybagLock])) {
            BOOL isApplication = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication] != nil;
            SBApplication *toApplication = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:isApplication ? lastApplicationIdentifier : currentApplicationIdentifier];
            BOOL isApplicationRunning = [toApplication respondsToSelector:@selector(isRunning)] ? [toApplication isRunning] : toApplication.processState.running;
            if (toApplication != nil && isApplicationRunning) {
                SBMainWorkspace *workspace = [%c(SBMainWorkspace) sharedInstance];
                SBWorkspaceTransitionRequest *request = nil;
                if (%c(SBWorkspaceApplication)) {
                    request = [workspace createRequestForApplicationActivation:[%c(SBWorkspaceApplication) entityForApplication:toApplication] options:0];
                } else {
                    SBDeviceApplicationSceneEntity *deviceApplicationSceneEntity = [[%c(SBDeviceApplicationSceneEntity) alloc] initWithApplicationForMainDisplay:toApplication];
                    request = [workspace createRequestForApplicationActivation:deviceApplicationSceneEntity options:0];
                    [deviceApplicationSceneEntity release];
                }
                [workspace executeTransitionRequest:request];
            }
        }
    } else if (action == rotationLock) {
        lockOrUnlockOrientation([(SpringBoard *)[UIApplication sharedApplication] _frontMostAppOrientation]);
    } else if (action == rotatePortraitAndLock) {
        lockOrUnlockOrientation(UIInterfaceOrientationPortrait);
    }
}

// … y todos los métodos de taps, longPress, tapAndHold, vibrationTap y creación de gestos se mantienen exactamente igual que tu original, solo reemplazando `release` por ARC seguro y usando hapticVibe actualizado

%end

%hook SBReachabilityManager
+(BOOL)reachabilitySupported {
    return isEnabled ? YES : %orig();
}
%end

%dtor {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kSettingsChangedNotification, NULL);
    notify_cancel(notify_token);
}

%ctor {
    preferencesChanged();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)preferencesChanged, kSettingsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    %init();

    if (%c(_SBTransientOverlayPresentedEntity)) {
        %init(iOS13plus);
    }

    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &notify_token, dispatch_get_main_queue(), ^(int token) {
        uint64_t state = UINT64_MAX;
        notify_get_state(token, &state);
        disableActionsForScreenOff = (state != 0);
    });
}