import UIKit

// The principal class is GuardedApplication, so every UIEvent passes through it before reaching a view:
// that is where the app refuses the hardware keyboard (the remote answers to touch and nothing else).
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv,
                  NSStringFromClass(GuardedApplication.self), NSStringFromClass(AppDelegate.self))
