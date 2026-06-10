import Foundation
import CoreGraphics

// Load SidecarCore private framework
guard let handle = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW) else {
    fputs("SidecarCore framework failed to open\n", stderr)
    exit(1)
}

guard let managerClass = NSClassFromString("SidecarDisplayManager") as? NSObject.Type else {
    fputs("SidecarDisplayManager class not found\n", stderr)
    exit(1)
}

let manager = managerClass.init()

guard let devices = manager.perform(NSSelectorFromString("devices"))?.takeUnretainedValue() as? [NSObject] else {
    fputs("Failed to query reachable sidecar devices\n", stderr)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    let usage = """
    Usage: SidecarLauncher <command> [device_name] [-wired]

    Commands:
        devices                       List reachable sidecar devices
        toggle                        Toggle Sidecar connection (connect/disconnect)
        connect <device_name>         Connect to device
        connect <device_name> -wired  Force wired connection
        disconnect                    Disconnect active Sidecar session
        status                        Check if Sidecar is connected

    Exit Codes:
        0    Success
        1    Invalid input
        2    No reachable Sidecar devices
        4    SidecarCore error
    """
    fputs(usage + "\n", stderr)
    exit(1)
}

let command = args[1]

func deviceName(_ obj: NSObject) -> String {
    return obj.perform(NSSelectorFromString("name"))?.takeUnretainedValue() as? String ?? "(unknown)"
}

func findDevice(named name: String) -> NSObject? {
    return devices.first { deviceName($0) == name }
}

// Detect Sidecar via CoreGraphics display list
// Works in all contexts (Dock apps, terminal, etc.) unlike system_profiler
// Sidecar/AirPlay displays have vendor ID 0x6161706c ("aapl") and are non-builtin
func isConnected() -> Bool {
    var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
    var displayCount: UInt32 = 0
    CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount)

    for i in 0..<Int(displayCount) {
        let displayID = onlineDisplays[i]
        if CGDisplayVendorNumber(displayID) == 0x6161706c && CGDisplayIsBuiltin(displayID) == 0 {
            return true
        }
    }
    return false
}

// Returns nil on success, error message on failure
func doConnect(deviceName name: String? = nil, wired: Bool = false) -> String? {
    let targetName = name ?? (devices.first.map { deviceName($0) })
    guard let targetName = targetName, let device = findDevice(named: targetName) else {
        return "No device found"
    }

    // Kill stale SidecarDisplayAgent for clean connection
    let killProc = Process()
    killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killProc.arguments = ["-9", "SidecarDisplayAgent"]
    killProc.standardOutput = FileHandle.nullDevice
    killProc.standardError = FileHandle.nullDevice
    try? killProc.run()
    killProc.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.5)

    let semaphore = DispatchSemaphore(value: 0)
    var connectError: NSError?

    if wired, let config = manager.perform(NSSelectorFromString("configForDevice:"), with: device)?.takeUnretainedValue() as? NSObject {
        config.perform(NSSelectorFromString("setTransport:"), with: 1 as NSNumber)
        let completion: @convention(block) (NSError?) -> Void = { error in
            connectError = error
            semaphore.signal()
        }
        let sel = NSSelectorFromString("connectToDevice:withConfig:completion:")
        let imp = manager.method(for: sel)
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, Any) -> Void
        unsafeBitCast(imp, to: Fn.self)(manager, sel, device, config, completion)
    } else {
        let completion: @convention(block) (NSError?) -> Void = { error in
            connectError = error
            semaphore.signal()
        }
        let sel = NSSelectorFromString("connectToDevice:completion:")
        let imp = manager.method(for: sel)
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, Any) -> Void
        unsafeBitCast(imp, to: Fn.self)(manager, sel, device, completion)
    }

    let timeout = semaphore.wait(timeout: .now() + 30)
    if timeout == .timedOut {
        return "Connection timed out"
    }

    if let error = connectError {
        if error.domain == "SidecarErrorDomain" {
            return "Sidecar error (\(error.code))"
        }
        return "Connection failed"
    }
    print("connected")
    return nil
}

func doDisconnect() {
    // Save recents, then clear them so relay doesn't auto-reconnect on respawn
    let defaults = UserDefaults(suiteName: "com.apple.sidecar.display")
    let savedRecents = defaults?.array(forKey: "recents") ?? []
    defaults?.removeObject(forKey: "recents")
    defaults?.synchronize()

    // Kill display agent and relay
    for name in ["SidecarDisplayAgent", "SidecarRelay"] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = ["-9", name]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    // Wait for relay to respawn in idle state, then restore recents
    Thread.sleep(forTimeInterval: 2.0)
    defaults?.set(savedRecents, forKey: "recents")
    defaults?.synchronize()
    print("disconnected")
}

// Check if an iPad is connected via USB
func isIPadUSBConnected() -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    proc.arguments = ["-p", "IOUSB", "-w0"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.contains("iPad")
}

// Check if StreamMode is ON (awdl0 down = wireless Sidecar broken)
func isStreamModeOn() -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    proc.arguments = ["awdl0"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.contains("status: inactive")
}

func sendNotification(_ message: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", "display notification \"\(message)\" with title \"Sidecar\""]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
}

switch command {
case "devices":
    if devices.isEmpty {
        fputs("No sidecar capable devices detected\n", stderr)
        exit(2)
    }
    for device in devices {
        print(deviceName(device))
    }

case "status":
    if isConnected() {
        print("connected")
    } else {
        print("disconnected")
    }

case "toggle":
    if isConnected() {
        sendNotification("Disconnecting...")
        doDisconnect()
        sendNotification("Disconnected")
    } else {
        if devices.isEmpty {
            sendNotification("No iPad found")
            fputs("No device found\n", stderr)
            exit(2)
        }
        let streamMode = isStreamModeOn()
        let usbConnected = streamMode ? isIPadUSBConnected() : false
        if streamMode && !usbConnected {
            sendNotification("StreamMode is ON — connect USB or turn it off")
            fputs("StreamMode is ON (awdl0 down) and no iPad on USB\n", stderr)
            exit(4)
        }
        let name = deviceName(devices.first!)
        sendNotification("Connecting...")
        if let error = doConnect(deviceName: name, wired: usbConnected) {
            sendNotification(error)
            exit(4)
        }
        sendNotification("Connected to \(name)")
    }

case "connect":
    guard args.count >= 3 else {
        fputs("Device name required\n", stderr)
        exit(1)
    }
    let name = args[2]
    let wired = args.count >= 4 && args[3] == "-wired"
    if let error = doConnect(deviceName: name, wired: wired) {
        fputs("\(error)\n", stderr)
        exit(4)
    }

case "disconnect":
    if !isConnected() {
        fputs("No active Sidecar session\n", stderr)
        exit(0)
    }
    doDisconnect()

default:
    fputs("Invalid command: \(command)\n", stderr)
    exit(1)
}

dlclose(handle)
