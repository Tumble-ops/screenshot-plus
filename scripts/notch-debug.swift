// Sends a command to a running debug build of Screenshot+. See DebugHooks.swift.
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.screenshotplus.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
