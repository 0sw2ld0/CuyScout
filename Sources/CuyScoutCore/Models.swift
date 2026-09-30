import Foundation

public struct Device: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case simulator, physical }
    public let id: String
    public let name: String
    public let runtime: String
    public let state: String
    public let isAvailable: Bool
    public let kind: Kind

    public init(id: String, name: String, runtime: String, state: String, isAvailable: Bool = true, kind: Kind = .simulator) {
        self.id = id; self.name = name; self.runtime = runtime; self.state = state; self.isAvailable = isAvailable; self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case id, name, runtime, state, isAvailable, kind }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        runtime = try values.decode(String.self, forKey: .runtime)
        state = try values.decode(String.self, forKey: .state)
        isAvailable = try values.decode(Bool.self, forKey: .isAvailable)
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .simulator
    }
}

public struct SchedulerLease: Codable, Sendable, Equatable {
    public let deviceID: String
    public let sessionID: String
    public let port: Int
    public let lastHeartbeat: Date
    public let expiresAt: Date
    public init(deviceID: String, sessionID: String, port: Int, lastHeartbeat: Date, expiresAt: Date) { self.deviceID = deviceID; self.sessionID = sessionID; self.port = port; self.lastHeartbeat = lastHeartbeat; self.expiresAt = expiresAt }
}

public struct Session: Codable, Sendable, Equatable {
    public let id: String
    public let device: Device
    public let bundleIdentifier: String?
    public let createdAt: Date
    public let driverID: String
    public let automationPort: Int?
    /// `true` cuando la reserva del dispositivo caducó por inactividad: la sesión ya no
    /// acepta comandos y hay que cerrarla y abrir otra. Ausente en sesiones vigentes.
    public var leaseExpired: Bool? = nil
    public init(id: String, device: Device, bundleIdentifier: String?, createdAt: Date, driverID: String = "ios-simulator", automationPort: Int? = nil) { self.id = id; self.device = device; self.bundleIdentifier = bundleIdentifier; self.createdAt = createdAt; self.driverID = driverID; self.automationPort = automationPort }
}

public struct AlertSnapshot: Codable, Sendable, Equatable {
    public let text: String
    public let buttons: [String]
    public init(text: String, buttons: [String] = []) { self.text = text; self.buttons = buttons }
}

public struct Cookie: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let path: String?
    public let domain: String?
    public let secure: Bool
    public let httpOnly: Bool
    public let expiry: Double?
    public init(name: String, value: String, path: String? = nil, domain: String? = nil, secure: Bool = false, httpOnly: Bool = false, expiry: Double? = nil) { self.name = name; self.value = value; self.path = path; self.domain = domain; self.secure = secure; self.httpOnly = httpOnly; self.expiry = expiry }
}

public struct PermissionGrant: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let service: String
    public let granted: Bool
    public init(bundleIdentifier: String, service: String, granted: Bool) { self.bundleIdentifier = bundleIdentifier; self.service = service; self.granted = granted }
}

public struct BiometryResult: Codable, Sendable, Equatable {
    public let enrolled: Bool
    public let enabled: Bool
    public init(enrolled: Bool, enabled: Bool) { self.enrolled = enrolled; self.enabled = enabled }
}

public struct VisualDiffResult: Codable, Sendable, Equatable {
    public let identical: Bool
    public let differenceRatio: Double
    public let tolerance: Double
    public let pixelDifferences: Int
    public init(identical: Bool, differenceRatio: Double, tolerance: Double, pixelDifferences: Int) { self.identical = identical; self.differenceRatio = differenceRatio; self.tolerance = tolerance; self.pixelDifferences = pixelDifferences }
}

public struct TimelineEntry: Codable, Sendable, Equatable {
    public let id: Int
    public let timestamp: Date
    public let actionType: String
    public let success: Bool
    public let durationMilliseconds: Int
    public let error: String?
    public let screenshotBase64: String?
    public init(id: Int, timestamp: Date, actionType: String, success: Bool, durationMilliseconds: Int, error: String? = nil, screenshotBase64: String? = nil) { self.id = id; self.timestamp = timestamp; self.actionType = actionType; self.success = success; self.durationMilliseconds = durationMilliseconds; self.error = error; self.screenshotBase64 = screenshotBase64 }
}

public struct ArtifactDescriptor: Codable, Sendable, Equatable {
    public let sessionID: String
    public let deviceID: String
    public let deviceName: String
    public let driverID: String
    public let bundleIdentifier: String?
    public let eventCount: Int
    public let recordedStepCount: Int
    public let currentURL: String?
    public let savedAt: Date?
    public init(sessionID: String, deviceID: String, deviceName: String, driverID: String, bundleIdentifier: String?, eventCount: Int, recordedStepCount: Int, currentURL: String?, savedAt: Date?) { self.sessionID = sessionID; self.deviceID = deviceID; self.deviceName = deviceName; self.driverID = driverID; self.bundleIdentifier = bundleIdentifier; self.eventCount = eventCount; self.recordedStepCount = recordedStepCount; self.currentURL = currentURL; self.savedAt = savedAt }
}

public struct ArtifactRestorePreflight: Codable, Sendable, Equatable {
    public let valid: Bool
    public let sessionID: String?
    public let deviceID: String?
    public let driverID: String?
    public let errors: [String]
    public let warnings: [String]
    public init(valid: Bool, sessionID: String? = nil, deviceID: String? = nil, driverID: String? = nil, errors: [String] = [], warnings: [String] = []) { self.valid = valid; self.sessionID = sessionID; self.deviceID = deviceID; self.driverID = driverID; self.errors = errors; self.warnings = warnings }
}

/// Preparation applies only to a temporary replay session, never to the saved artifact.
public enum ReplayPreparationMode: String, Codable, Sendable, CaseIterable {
    /// Attach to an already running app when possible; otherwise launch it. Keeps app data.
    case preserve
    /// Restart the app process while keeping its installed data and simulator keychain.
    case restart
    /// Uninstall then install the supplied app. Clears its container, but not the simulator keychain.
    case reinstall
}

public struct ReplayPreflight: Codable, Sendable, Equatable {
    public let ready: Bool
    public let artifactID: String
    public let recordedDeviceID: String
    public let selectedDevice: Device?
    public let availableDevices: [Device]
    public let preparation: ReplayPreparationMode
    public let runnerReady: Bool
    public let runnerCanBuild: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(artifactID: String, recordedDeviceID: String, selectedDevice: Device?, availableDevices: [Device], preparation: ReplayPreparationMode, runnerReady: Bool, runnerCanBuild: Bool, errors: [String], warnings: [String]) {
        self.ready = errors.isEmpty
        self.artifactID = artifactID
        self.recordedDeviceID = recordedDeviceID
        self.selectedDevice = selectedDevice
        self.availableDevices = availableDevices
        self.preparation = preparation
        self.runnerReady = runnerReady
        self.runnerCanBuild = runnerCanBuild
        self.errors = errors
        self.warnings = warnings
    }
}

public enum ScoutAction: Codable, Sendable, Equatable {
    case launch(bundleIdentifier: String)
    case terminate(bundleIdentifier: String)
    case backgroundApp(duration: Double)
    case openURL(String)
    case navigateBack
    case navigateForward
    case refresh
    case acceptAlert
    case dismissAlert
    case rotate(DeviceOrientation)
    case getClipboard
    case setClipboard(String)
    case screenshot
    case tap(x: Double, y: Double)
    case swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double)
    case type(String)
    case accessibilityTree
    case findElement(ScoutSelector)
    case findElements(ScoutSelector)
    case tapElement(ScoutSelector)
    case typeElement(ScoutSelector, text: String)
    case waitFor(ScoutSelector, timeout: Double)
    case assertVisible(ScoutSelector)
    case assertText(ScoutSelector, expected: String)
    case accessibilityTreeWithOptions(AccessibilityOptions)
    case accessibilityDiff(AccessibilityOptions)
    case sequence([ScoutAction])
    case clearElement(ScoutSelector)
    case elementAttribute(ScoutSelector, name: String)
    case elementDisplayed(ScoutSelector)
    case elementEnabled(ScoutSelector)
    case elementRect(ScoutSelector)
    case elementScreenshot(ScoutSelector)
    case findElementFromElement(parent: ScoutSelector, child: ScoutSelector)
    case findElementsFromElement(parent: ScoutSelector, child: ScoutSelector)
    case elementSelected(ScoutSelector)
    case elementName(ScoutSelector)
    case scroll(x: Double, y: Double)
    case alertText(String)
    case elementProperty(ScoutSelector, name: String)
    case activeElement
    case grantPermission(bundleIdentifier: String, service: String)
    case setBiometry(enrolled: Bool, enabled: Bool)
    case setLocation(latitude: Double, longitude: Double)
    case visualDiff(tolerance: Double)
    case submit(ScoutSelector)
    case setAppearance(String)
    case setStatusBar(time: String?, dataNetwork: String?, wifiMode: String?, batteryLevel: Int?, batteryState: String?)
    case startVideoRecording(String)
    case stopVideoRecording
    case listApps
    case resetKeychain
    case deepLink(String)
    case pushNotification(bundleIdentifier: String, payloadPath: String)
    case setContentSize(String)
    case addMedia(String)
    case spawnProcess(bundleIdentifier: String, args: [String])
    case icloudSync
    case shake
    case doubleTap(ScoutSelector)
    case longPress(ScoutSelector, duration: Double)
    case pinch(scale: Double, velocity: Double)
    case enumerateFiles(String)
    case downloadFile(source: String, destination: String)
    case uploadFile(source: String, destination: String)
    case getAppContainer(bundleIdentifier: String, container: String)
    case getConfig(String)
    case setConfig(key: String, value: String)

    private enum CodingKeys: String, CodingKey { case type, bundleIdentifier, url, orientation, text, x, y, fromX, fromY, toX, toY, duration, selector, timeout, expected, options, actions, name, parent, child, service, enrolled, enabled, latitude, longitude, tolerance, path, time, dataNetwork, wifiMode, batteryLevel, batteryState, payloadPath, args, scale, velocity, source, destination, container, key, value }
    private enum Kind: String, Codable { case launch, terminate, backgroundApp, openURL, navigateBack, navigateForward, refresh, acceptAlert, dismissAlert, rotate, getClipboard, setClipboard, screenshot, tap, swipe, type, accessibilityTree, findElement, findElements, tapElement, typeElement, waitFor, assertVisible, assertText, accessibilityTreeWithOptions, accessibilityDiff, sequence, clearElement, elementAttribute, elementDisplayed, elementEnabled, elementRect, elementScreenshot, findElementFromElement, findElementsFromElement, elementSelected, elementName, scroll, alertText, elementProperty, activeElement, grantPermission, setBiometry, setLocation, visualDiff, submit, setAppearance, setStatusBar, startVideoRecording, stopVideoRecording, listApps, resetKeychain, deepLink, pushNotification, setContentSize, addMedia, spawnProcess, icloudSync, shake, doubleTap, longPress, pinch, enumerateFiles, downloadFile, uploadFile, getAppContainer, getConfig, setConfig }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .launch: self = .launch(bundleIdentifier: try c.decode(String.self, forKey: .bundleIdentifier))
        case .terminate: self = .terminate(bundleIdentifier: try c.decode(String.self, forKey: .bundleIdentifier))
        case .backgroundApp: self = .backgroundApp(duration: try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0)
        case .openURL: self = .openURL(try c.decode(String.self, forKey: .url))
        case .navigateBack: self = .navigateBack
        case .navigateForward: self = .navigateForward
        case .refresh: self = .refresh
        case .acceptAlert: self = .acceptAlert
        case .dismissAlert: self = .dismissAlert
        case .rotate: self = .rotate(try c.decode(DeviceOrientation.self, forKey: .orientation))
        case .getClipboard: self = .getClipboard
        case .setClipboard: self = .setClipboard(try c.decode(String.self, forKey: .text))
        case .screenshot: self = .screenshot
        case .tap: self = .tap(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
        case .swipe: self = .swipe(fromX: try c.decode(Double.self, forKey: .fromX), fromY: try c.decode(Double.self, forKey: .fromY), toX: try c.decode(Double.self, forKey: .toX), toY: try c.decode(Double.self, forKey: .toY), duration: try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0.3)
        case .type: self = .type(try c.decode(String.self, forKey: .text))
        case .accessibilityTree: self = .accessibilityTree
        case .findElement: self = .findElement(try c.decode(ScoutSelector.self, forKey: .selector))
        case .findElements: self = .findElements(try c.decode(ScoutSelector.self, forKey: .selector))
        case .tapElement: self = .tapElement(try c.decode(ScoutSelector.self, forKey: .selector))
        case .typeElement: self = .typeElement(try c.decode(ScoutSelector.self, forKey: .selector), text: try c.decode(String.self, forKey: .text))
        case .waitFor: self = .waitFor(try c.decode(ScoutSelector.self, forKey: .selector), timeout: try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 10)
        case .assertVisible: self = .assertVisible(try c.decode(ScoutSelector.self, forKey: .selector))
        case .assertText: self = .assertText(try c.decode(ScoutSelector.self, forKey: .selector), expected: try c.decode(String.self, forKey: .expected))
        case .accessibilityTreeWithOptions: self = .accessibilityTreeWithOptions(try c.decode(AccessibilityOptions.self, forKey: .options))
        case .accessibilityDiff: self = .accessibilityDiff(try c.decode(AccessibilityOptions.self, forKey: .options))
        case .sequence: self = .sequence(try c.decode([ScoutAction].self, forKey: .actions))
        case .clearElement: self = .clearElement(try c.decode(ScoutSelector.self, forKey: .selector))
        case .elementAttribute: self = .elementAttribute(try c.decode(ScoutSelector.self, forKey: .selector), name: try c.decode(String.self, forKey: .name))
        case .elementDisplayed: self = .elementDisplayed(try c.decode(ScoutSelector.self, forKey: .selector))
        case .elementEnabled: self = .elementEnabled(try c.decode(ScoutSelector.self, forKey: .selector))
        case .elementRect: self = .elementRect(try c.decode(ScoutSelector.self, forKey: .selector))
        case .elementScreenshot: self = .elementScreenshot(try c.decode(ScoutSelector.self, forKey: .selector))
        case .findElementFromElement: self = .findElementFromElement(parent: try c.decode(ScoutSelector.self, forKey: .parent), child: try c.decode(ScoutSelector.self, forKey: .child))
        case .findElementsFromElement: self = .findElementsFromElement(parent: try c.decode(ScoutSelector.self, forKey: .parent), child: try c.decode(ScoutSelector.self, forKey: .child))
        case .elementSelected: self = .elementSelected(try c.decode(ScoutSelector.self, forKey: .selector))
        case .elementName: self = .elementName(try c.decode(ScoutSelector.self, forKey: .selector))
        case .scroll: self = .scroll(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
        case .alertText: self = .alertText(try c.decode(String.self, forKey: .text))
        case .elementProperty: self = .elementProperty(try c.decode(ScoutSelector.self, forKey: .selector), name: try c.decode(String.self, forKey: .name))
        case .activeElement: self = .activeElement
        case .grantPermission: self = .grantPermission(bundleIdentifier: try c.decode(String.self, forKey: .bundleIdentifier), service: try c.decode(String.self, forKey: .service))
        case .setBiometry: self = .setBiometry(enrolled: try c.decode(Bool.self, forKey: .enrolled), enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true)
        case .setLocation: self = .setLocation(latitude: try c.decode(Double.self, forKey: .latitude), longitude: try c.decode(Double.self, forKey: .longitude))
        case .visualDiff: self = .visualDiff(tolerance: try c.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0.1)
        case .submit: self = .submit(try c.decode(ScoutSelector.self, forKey: .selector))
        case .setAppearance: self = .setAppearance(try c.decode(String.self, forKey: .text))
        case .setStatusBar: self = .setStatusBar(time: try c.decodeIfPresent(String.self, forKey: .time), dataNetwork: try c.decodeIfPresent(String.self, forKey: .dataNetwork), wifiMode: try c.decodeIfPresent(String.self, forKey: .wifiMode), batteryLevel: try c.decodeIfPresent(Int.self, forKey: .batteryLevel), batteryState: try c.decodeIfPresent(String.self, forKey: .batteryState))
        case .startVideoRecording: self = .startVideoRecording(try c.decode(String.self, forKey: .path))
        case .stopVideoRecording: self = .stopVideoRecording
        case .listApps: self = .listApps
        case .resetKeychain: self = .resetKeychain
        case .deepLink: self = .deepLink(try c.decode(String.self, forKey: .url))
        case .pushNotification: self = .pushNotification(bundleIdentifier: try c.decode(String.self, forKey: .bundleIdentifier), payloadPath: try c.decode(String.self, forKey: .payloadPath))
        case .setContentSize: self = .setContentSize(try c.decode(String.self, forKey: .text))
        case .addMedia: self = .addMedia(try c.decode(String.self, forKey: .path))
        case .spawnProcess: self = .spawnProcess(bundleIdentifier: try c.decode(String.self, forKey: .bundleIdentifier), args: try c.decodeIfPresent([String].self, forKey: .args) ?? [])
        case .icloudSync: self = .icloudSync
        case .shake: self = .shake
        case .doubleTap: self = .doubleTap(try c.decode(ScoutSelector.self, forKey: .selector))
        case .longPress: self = .longPress(try c.decode(ScoutSelector.self, forKey: .selector), duration: try c.decodeIfPresent(Double.self, forKey: .duration) ?? 1.0)
        case .pinch: self = .pinch(scale: try c.decode(Double.self, forKey: .scale), velocity: try c.decodeIfPresent(Double.self, forKey: .velocity) ?? 1.0)
        case .enumerateFiles: self = .enumerateFiles(try c.decode(String.self, forKey: .path))
        case .downloadFile: self = .downloadFile(source: try c.decode(String.self, forKey: .source), destination: try c.decode(String.self, forKey: .destination))
        case .uploadFile: self = .uploadFile(source: try c.decode(String.self, forKey: .source), destination: try c.decode(String.self, forKey: .destination))
        case .getAppContainer: self = .getAppContainer(bundleIdentifier: try c.decode(String.self, forKey: .bundleIdentifier), container: try c.decodeIfPresent(String.self, forKey: .container) ?? "data")
        case .getConfig: self = .getConfig(try c.decode(String.self, forKey: .key))
        case .setConfig: self = .setConfig(key: try c.decode(String.self, forKey: .key), value: try c.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .launch(let b): try c.encode(Kind.launch, forKey: .type); try c.encode(b, forKey: .bundleIdentifier)
        case .terminate(let b): try c.encode(Kind.terminate, forKey: .type); try c.encode(b, forKey: .bundleIdentifier)
        case .backgroundApp(let duration): try c.encode(Kind.backgroundApp, forKey: .type); try c.encode(duration, forKey: .duration)
        case .openURL(let u): try c.encode(Kind.openURL, forKey: .type); try c.encode(u, forKey: .url)
        case .navigateBack: try c.encode(Kind.navigateBack, forKey: .type)
        case .navigateForward: try c.encode(Kind.navigateForward, forKey: .type)
        case .refresh: try c.encode(Kind.refresh, forKey: .type)
        case .acceptAlert: try c.encode(Kind.acceptAlert, forKey: .type)
        case .dismissAlert: try c.encode(Kind.dismissAlert, forKey: .type)
        case .rotate(let orientation): try c.encode(Kind.rotate, forKey: .type); try c.encode(orientation, forKey: .orientation)
        case .getClipboard: try c.encode(Kind.getClipboard, forKey: .type)
        case .setClipboard(let text): try c.encode(Kind.setClipboard, forKey: .type); try c.encode(text, forKey: .text)
        case .screenshot: try c.encode(Kind.screenshot, forKey: .type)
        case .tap(let x, let y): try c.encode(Kind.tap, forKey: .type); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        case .swipe(let fx, let fy, let tx, let ty, let d): try c.encode(Kind.swipe, forKey: .type); try c.encode(fx, forKey: .fromX); try c.encode(fy, forKey: .fromY); try c.encode(tx, forKey: .toX); try c.encode(ty, forKey: .toY); try c.encode(d, forKey: .duration)
        case .type(let text): try c.encode(Kind.type, forKey: .type); try c.encode(text, forKey: .text)
        case .accessibilityTree: try c.encode(Kind.accessibilityTree, forKey: .type)
        case .findElement(let selector): try c.encode(Kind.findElement, forKey: .type); try c.encode(selector, forKey: .selector)
        case .findElements(let selector): try c.encode(Kind.findElements, forKey: .type); try c.encode(selector, forKey: .selector)
        case .tapElement(let selector): try c.encode(Kind.tapElement, forKey: .type); try c.encode(selector, forKey: .selector)
        case .typeElement(let selector, let text): try c.encode(Kind.typeElement, forKey: .type); try c.encode(selector, forKey: .selector); try c.encode(text, forKey: .text)
        case .waitFor(let selector, let timeout): try c.encode(Kind.waitFor, forKey: .type); try c.encode(selector, forKey: .selector); try c.encode(timeout, forKey: .timeout)
        case .assertVisible(let selector): try c.encode(Kind.assertVisible, forKey: .type); try c.encode(selector, forKey: .selector)
        case .assertText(let selector, let expected): try c.encode(Kind.assertText, forKey: .type); try c.encode(selector, forKey: .selector); try c.encode(expected, forKey: .expected)
        case .accessibilityTreeWithOptions(let options): try c.encode(Kind.accessibilityTreeWithOptions, forKey: .type); try c.encode(options, forKey: .options)
        case .accessibilityDiff(let options): try c.encode(Kind.accessibilityDiff, forKey: .type); try c.encode(options, forKey: .options)
        case .sequence(let actions): try c.encode(Kind.sequence, forKey: .type); try c.encode(actions, forKey: .actions)
        case .clearElement(let selector): try c.encode(Kind.clearElement, forKey: .type); try c.encode(selector, forKey: .selector)
        case .elementAttribute(let selector, let name): try c.encode(Kind.elementAttribute, forKey: .type); try c.encode(selector, forKey: .selector); try c.encode(name, forKey: .name)
        case .elementDisplayed(let selector): try c.encode(Kind.elementDisplayed, forKey: .type); try c.encode(selector, forKey: .selector)
        case .elementEnabled(let selector): try c.encode(Kind.elementEnabled, forKey: .type); try c.encode(selector, forKey: .selector)
        case .elementRect(let selector): try c.encode(Kind.elementRect, forKey: .type); try c.encode(selector, forKey: .selector)
        case .elementScreenshot(let selector): try c.encode(Kind.elementScreenshot, forKey: .type); try c.encode(selector, forKey: .selector)
        case .findElementFromElement(let parent, let child): try c.encode(Kind.findElementFromElement, forKey: .type); try c.encode(parent, forKey: .parent); try c.encode(child, forKey: .child)
        case .findElementsFromElement(let parent, let child): try c.encode(Kind.findElementsFromElement, forKey: .type); try c.encode(parent, forKey: .parent); try c.encode(child, forKey: .child)
        case .elementSelected(let selector): try c.encode(Kind.elementSelected, forKey: .type); try c.encode(selector, forKey: .selector)
        case .elementName(let selector): try c.encode(Kind.elementName, forKey: .type); try c.encode(selector, forKey: .selector)
        case .scroll(let x, let y): try c.encode(Kind.scroll, forKey: .type); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        case .alertText(let text): try c.encode(Kind.alertText, forKey: .type); try c.encode(text, forKey: .text)
        case .elementProperty(let selector, let name): try c.encode(Kind.elementProperty, forKey: .type); try c.encode(selector, forKey: .selector); try c.encode(name, forKey: .name)
        case .activeElement: try c.encode(Kind.activeElement, forKey: .type)
        case .grantPermission(let bundle, let service): try c.encode(Kind.grantPermission, forKey: .type); try c.encode(bundle, forKey: .bundleIdentifier); try c.encode(service, forKey: .service)
        case .setBiometry(let enrolled, let enabled): try c.encode(Kind.setBiometry, forKey: .type); try c.encode(enrolled, forKey: .enrolled); try c.encode(enabled, forKey: .enabled)
        case .setLocation(let latitude, let longitude): try c.encode(Kind.setLocation, forKey: .type); try c.encode(latitude, forKey: .latitude); try c.encode(longitude, forKey: .longitude)
        case .visualDiff(let tolerance): try c.encode(Kind.visualDiff, forKey: .type); try c.encode(tolerance, forKey: .tolerance)
        case .submit(let selector): try c.encode(Kind.submit, forKey: .type); try c.encode(selector, forKey: .selector)
        case .setAppearance(let mode): try c.encode(Kind.setAppearance, forKey: .type); try c.encode(mode, forKey: .text)
        case .setStatusBar(let time, let dataNetwork, let wifiMode, let batteryLevel, let batteryState): try c.encode(Kind.setStatusBar, forKey: .type); try c.encodeIfPresent(time, forKey: .time); try c.encodeIfPresent(dataNetwork, forKey: .dataNetwork); try c.encodeIfPresent(wifiMode, forKey: .wifiMode); try c.encodeIfPresent(batteryLevel, forKey: .batteryLevel); try c.encodeIfPresent(batteryState, forKey: .batteryState)
        case .startVideoRecording(let path): try c.encode(Kind.startVideoRecording, forKey: .type); try c.encode(path, forKey: .path)
        case .stopVideoRecording: try c.encode(Kind.stopVideoRecording, forKey: .type)
        case .listApps: try c.encode(Kind.listApps, forKey: .type)
        case .resetKeychain: try c.encode(Kind.resetKeychain, forKey: .type)
        case .deepLink(let url): try c.encode(Kind.deepLink, forKey: .type); try c.encode(url, forKey: .url)
        case .pushNotification(let bundle, let payloadPath): try c.encode(Kind.pushNotification, forKey: .type); try c.encode(bundle, forKey: .bundleIdentifier); try c.encode(payloadPath, forKey: .payloadPath)
        case .setContentSize(let size): try c.encode(Kind.setContentSize, forKey: .type); try c.encode(size, forKey: .text)
        case .addMedia(let path): try c.encode(Kind.addMedia, forKey: .type); try c.encode(path, forKey: .path)
        case .spawnProcess(let bundle, let args): try c.encode(Kind.spawnProcess, forKey: .type); try c.encode(bundle, forKey: .bundleIdentifier); try c.encode(args, forKey: .args)
        case .icloudSync: try c.encode(Kind.icloudSync, forKey: .type)
        case .shake: try c.encode(Kind.shake, forKey: .type)
        case .doubleTap(let selector): try c.encode(Kind.doubleTap, forKey: .type); try c.encode(selector, forKey: .selector)
        case .longPress(let selector, let duration): try c.encode(Kind.longPress, forKey: .type); try c.encode(selector, forKey: .selector); try c.encode(duration, forKey: .duration)
        case .pinch(let scale, let velocity): try c.encode(Kind.pinch, forKey: .type); try c.encode(scale, forKey: .scale); try c.encode(velocity, forKey: .velocity)
        case .enumerateFiles(let path): try c.encode(Kind.enumerateFiles, forKey: .type); try c.encode(path, forKey: .path)
        case .downloadFile(let source, let destination): try c.encode(Kind.downloadFile, forKey: .type); try c.encode(source, forKey: .source); try c.encode(destination, forKey: .destination)
        case .uploadFile(let source, let destination): try c.encode(Kind.uploadFile, forKey: .type); try c.encode(source, forKey: .source); try c.encode(destination, forKey: .destination)
        case .getAppContainer(let bundle, let container): try c.encode(Kind.getAppContainer, forKey: .type); try c.encode(bundle, forKey: .bundleIdentifier); try c.encode(container, forKey: .container)
        case .getConfig(let key): try c.encode(Kind.getConfig, forKey: .type); try c.encode(key, forKey: .key)
        case .setConfig(let key, let value): try c.encode(Kind.setConfig, forKey: .type); try c.encode(key, forKey: .key); try c.encode(value, forKey: .value)
        }
    }
}

public extension ScoutAction {
    func redactedSensitiveData() -> ScoutAction {
        switch self {
        case .type: return .type("<redacted>")
        case .setClipboard: return .setClipboard("<redacted>")
        case .typeElement(let selector, _): return .typeElement(selector, text: "<redacted>")
        case .assertText(let selector, _): return .assertText(selector, expected: "<redacted>")
        case .sequence(let actions): return .sequence(actions.map { $0.redactedSensitiveData() })
        default: return self
        }
    }
}

public struct BridgeCommand: Codable, Sendable, Equatable {
    public let id: String
    public let action: ScoutAction
    public init(id: String = UUID().uuidString, action: ScoutAction) { self.id = id; self.action = action }
}

public struct BridgeResult: Codable, Sendable, Equatable {
    public let commandID: String
    public let success: Bool
    public let payloadBase64: String?
    public let error: String?
    /// Código del runner XCTest, para traducir el fallo a un error W3C concreto en vez de
    /// un `unknown error` genérico. `8` es "no such element".
    public let errorCode: Int?
    public init(commandID: String, success: Bool, payloadBase64: String? = nil, error: String? = nil, errorCode: Int? = nil) { self.commandID = commandID; self.success = success; self.payloadBase64 = payloadBase64; self.error = error; self.errorCode = errorCode }
}

/// Comando que un adaptador WebKit puede ejecutar dentro de un contexto WEBVIEW.
/// `argumentsJSON` conserva los argumentos como JSON sin imponer un tipo dinámico
/// en el núcleo Swift.
public struct WebViewCommand: Codable, Sendable, Equatable {
    public let id: String
    public let context: String
    public let script: String
    public let argumentsJSON: String

    public init(id: String = UUID().uuidString, context: String, script: String, argumentsJSON: String = "[]") {
        self.id = id; self.context = context; self.script = script; self.argumentsJSON = argumentsJSON
    }
}

public struct WebViewResult: Codable, Sendable, Equatable {
    public let commandID: String
    public let success: Bool
    public let valueJSON: String?
    public let error: String?

    public init(commandID: String, success: Bool, valueJSON: String? = nil, error: String? = nil) {
        self.commandID = commandID; self.success = success; self.valueJSON = valueJSON; self.error = error
    }
}

public struct WebViewStatus: Codable, Sendable, Equatable {
    public let connected: Bool
    public let contexts: [String]
    public let currentContext: String
    public init(connected: Bool, contexts: [String], currentContext: String) {
        self.connected = connected; self.contexts = contexts; self.currentContext = currentContext
    }
}

public struct PageInfo: Codable, Sendable, Equatable {
    public let context: String
    public let url: String
    public let title: String
    public let sourceLength: Int
    public init(context: String, url: String, title: String, sourceLength: Int) {
        self.context = context; self.url = url; self.title = title; self.sourceLength = sourceLength
    }
}

public struct ActionSuggestion: Codable, Sendable, Equatable {
    public let action: ScoutAction
    public let reason: String
    public let risk: String?
    public init(action: ScoutAction, reason: String, risk: String? = nil) { self.action = action; self.reason = reason; self.risk = risk }
}

/// App ya instalada en un dispositivo: se puede probar sin su instalador.
public struct InstalledApp: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let name: String
    public let version: String?
    /// Compilación de desarrollo (firmada para depurar), la que XCUITest puede controlar.
    public let developerBuild: Bool
    public init(bundleIdentifier: String, name: String, version: String?, developerBuild: Bool) { self.bundleIdentifier = bundleIdentifier; self.name = name; self.version = version; self.developerBuild = developerBuild }
}

public struct DoctorCheck: Codable, Sendable, Equatable {
    public let name: String
    public let available: Bool
    public let detail: String
    public init(name: String, available: Bool, detail: String) { self.name = name; self.available = available; self.detail = detail }
}

public struct DoctorReport: Codable, Sendable, Equatable {
    public let ready: Bool
    public let checks: [DoctorCheck]
    public let recommendations: [String]
    public init(ready: Bool, checks: [DoctorCheck], recommendations: [String]) { self.ready = ready; self.checks = checks; self.recommendations = recommendations }
}

public struct AgentObservation: Codable, Sendable, Equatable {
    public let context: String
    public let url: String
    public let title: String
    public let stateId: String
    public let changed: Bool
    public let actions: [ActionSuggestion]
    /// Textos visibles de la pantalla, con su identificador cuando lo tienen. Es lo que el
    /// agente necesita para VERIFICAR (un importe, un número de operación, un mensaje de
    /// error) frente a `actions`, que es lo que necesita para ACTUAR. Sin esto el agente se
    /// ve obligado a descargar el árbol de accesibilidad completo, que cuesta un orden de
    /// magnitud más y contiene sobre todo geometría y contenedores anónimos.
    public let texts: [String]
    public let exploration: ExplorationReport?
    public init(context: String, url: String, title: String, stateId: String, changed: Bool, actions: [ActionSuggestion], texts: [String] = [], exploration: ExplorationReport?) { self.context = context; self.url = url; self.title = title; self.stateId = stateId; self.changed = changed; self.actions = actions; self.texts = texts; self.exploration = exploration }
}

/// Estado agregado para que un agente pueda decidir con una sola lectura compacta.
public struct AgentEventSummary: Codable, Sendable, Equatable {
    public let id: Int
    public let kind: String
    public let success: Bool
    public let durationMilliseconds: Int
    public let error: String?
    public init(id: Int, kind: String, success: Bool, durationMilliseconds: Int, error: String? = nil) {
        self.id = id; self.kind = kind; self.success = success; self.durationMilliseconds = durationMilliseconds; self.error = error
    }
}

public struct SessionReadiness: Codable, Sendable, Equatable {
    public let interactionReady: Bool
    public let context: String
    public let xctestBridgeConnected: Bool
    public let webViewConnected: Bool
    public let commandsUsed: Int
    public let commandsRemaining: Int?
    public let blockers: [String]
    public init(interactionReady: Bool, context: String, xctestBridgeConnected: Bool, webViewConnected: Bool, commandsUsed: Int = 0, commandsRemaining: Int? = nil, blockers: [String]) {
        self.interactionReady = interactionReady; self.context = context; self.xctestBridgeConnected = xctestBridgeConnected; self.webViewConnected = webViewConnected; self.commandsUsed = commandsUsed; self.commandsRemaining = commandsRemaining; self.blockers = blockers
    }
}

public struct SessionHealthSnapshot: Codable, Sendable, Equatable {
    public let sessionID: String
    public let healthy: Bool
    public let context: String
    public let blockers: [String]
    public let commandsUsed: Int
    public let commandsRemaining: Int?
    public let failureRate: Double
    public let p95DurationMilliseconds: Int
    public init(sessionID: String, healthy: Bool, context: String, blockers: [String], commandsUsed: Int, commandsRemaining: Int?, failureRate: Double, p95DurationMilliseconds: Int) { self.sessionID = sessionID; self.healthy = healthy; self.context = context; self.blockers = blockers; self.commandsUsed = commandsUsed; self.commandsRemaining = commandsRemaining; self.failureRate = failureRate; self.p95DurationMilliseconds = p95DurationMilliseconds }
}

public struct AgentStateSnapshot: Codable, Sendable, Equatable {
    public let sessionID: String
    public let observation: AgentObservation
    public let metrics: SessionMetrics
    public let recentEvents: [AgentEventSummary]
    public let coverage: ExplorationCoverage
    public let readiness: SessionReadiness
    public let loopDetected: Bool
    public let nextActionHint: String?
    public let lessons: [LearnedLesson]
    /// Presente solo con Laya activo: el agente puede delegarle la elección del control.
    public let decision: DecisionEngineInfo?
    public init(sessionID: String, observation: AgentObservation, metrics: SessionMetrics, recentEvents: [AgentEventSummary], coverage: ExplorationCoverage, readiness: SessionReadiness, loopDetected: Bool, nextActionHint: String?, lessons: [LearnedLesson] = [], decision: DecisionEngineInfo? = nil) {
        self.sessionID = sessionID; self.observation = observation; self.metrics = metrics; self.recentEvents = recentEvents; self.coverage = coverage; self.readiness = readiness; self.loopDetected = loopDetected; self.nextActionHint = nextActionHint; self.lessons = lessons; self.decision = decision
    }
}

public struct DecisionEngineInfo: Codable, Sendable, Equatable {
    public let engine: String
    public let endpoint: String
    public let usage: String
    public init(engine: String, endpoint: String, usage: String) { self.engine = engine; self.endpoint = endpoint; self.usage = usage }

    public static func current(_ layaSwitch: LayaSwitch = .shared) -> DecisionEngineInfo? {
        guard layaSwitch.settings.enabled else { return nil }
        return DecisionEngineInfo(engine: "laya", endpoint: "POST /session/:id/decide",
            usage: "Envía {step, intent: tocar|escribir|seleccionar|confirmar, options? (valor a elegir), avoid? (valores a no elegir), exclude? (selectores ya usados), context?}. Con decision=chosen ejecuta candidate.action (en un campo reemplaza <text> por el valor); con needs_llm elige tú entre candidates. Verificar sigue siendo tuyo: usa los textos de observe.")
    }
}

public struct NavigationTransition: Codable, Sendable, Equatable {
    public let fromState: String
    public let toState: String
    public let action: ScoutAction
    public init(fromState: String, toState: String, action: ScoutAction) { self.fromState = fromState; self.toState = toState; self.action = action }
}

public struct NavigationGraph: Codable, Sendable, Equatable {
    public let states: [String]
    public let transitions: [NavigationTransition]
    public init(states: [String], transitions: [NavigationTransition]) { self.states = states; self.transitions = transitions }
}

public struct ExplorationCoverage: Codable, Sendable, Equatable {
    public let stateCount: Int
    public let transitionCount: Int
    public let uniqueTransitionCount: Int
    public let repeatedTransitionCount: Int
    public let repeatedTransitionRate: Double
    public let loopRisk: Bool
    public let nextActionHint: String?
    public init(stateCount: Int, transitionCount: Int, uniqueTransitionCount: Int, repeatedTransitionCount: Int, repeatedTransitionRate: Double, loopRisk: Bool, nextActionHint: String?) {
        self.stateCount = stateCount; self.transitionCount = transitionCount; self.uniqueTransitionCount = uniqueTransitionCount; self.repeatedTransitionCount = repeatedTransitionCount; self.repeatedTransitionRate = repeatedTransitionRate; self.loopRisk = loopRisk; self.nextActionHint = nextActionHint
    }
}

public struct ScreenContractElement: Codable, Sendable, Equatable {
    public let identifier: String
    public let role: String
    public let label: String?
    public init(identifier: String, role: String, label: String? = nil) { self.identifier = identifier; self.role = role; self.label = label }
}

public struct ScreenContract: Codable, Sendable, Equatable {
    public let name: String
    public let stateId: String
    public let context: String
    public let elements: [ScreenContractElement]
    public let generatedAt: Date
    public init(name: String, stateId: String, context: String, elements: [ScreenContractElement], generatedAt: Date = Date()) { self.name = name; self.stateId = stateId; self.context = context; self.elements = elements; self.generatedAt = generatedAt }
}

public struct ScreenContractComparison: Codable, Sendable, Equatable {
    public let matches: Bool
    public let missing: [ScreenContractElement]
    public let changed: [ScreenContractElement]
    public let unexpected: [ScreenContractElement]
    public init(matches: Bool, missing: [ScreenContractElement], changed: [ScreenContractElement], unexpected: [ScreenContractElement]) { self.matches = matches; self.missing = missing; self.changed = changed; self.unexpected = unexpected }
}

public struct ExplorationCheckpoint: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let stateId: String
    public let stepCount: Int
    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), stateId: String, stepCount: Int) { self.id = id; self.name = name; self.createdAt = createdAt; self.stateId = stateId; self.stepCount = stepCount }
}

public struct TestPlanStep: Codable, Sendable, Equatable {
    public let id: String
    public let action: ScoutAction
    public let success: Bool
    public let durationMilliseconds: Int
    public init(id: String, action: ScoutAction, success: Bool, durationMilliseconds: Int) { self.id = id; self.action = action; self.success = success; self.durationMilliseconds = durationMilliseconds }
}

public struct TestPlan: Codable, Sendable, Equatable {
    public let sessionID: String
    public let steps: [TestPlanStep]
    public let warnings: [String]
    public init(sessionID: String, steps: [TestPlanStep], warnings: [String]) { self.sessionID = sessionID; self.steps = steps; self.warnings = warnings }
}

public struct CheckpointRestoreResult: Codable, Sendable, Equatable {
    public let checkpoint: ExplorationCheckpoint
    public let replayedSteps: Int
    public let resetPerformed: Bool
    public let warning: String?
    public init(checkpoint: ExplorationCheckpoint, replayedSteps: Int, resetPerformed: Bool, warning: String? = nil) { self.checkpoint = checkpoint; self.replayedSteps = replayedSteps; self.resetPerformed = resetPerformed; self.warning = warning }
}

public struct TestPlanValidation: Codable, Sendable, Equatable {
    public let valid: Bool
    public let executable: Bool
    public let errors: [String]
    public let warnings: [String]
    public init(valid: Bool, executable: Bool, errors: [String], warnings: [String]) { self.valid = valid; self.executable = executable; self.errors = errors; self.warnings = warnings }
}

public struct ReplayResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let executedSteps: Int
    public let totalSteps: Int
    public let failedStep: Int?
    public let error: String?
    public let durationMilliseconds: Int
    public let dismissedInterruptions: Int?
    public init(success: Bool, executedSteps: Int, totalSteps: Int, failedStep: Int? = nil, error: String? = nil, durationMilliseconds: Int, dismissedInterruptions: Int? = nil) { self.success = success; self.executedSteps = executedSteps; self.totalSteps = totalSteps; self.failedStep = failedStep; self.error = error; self.durationMilliseconds = durationMilliseconds; self.dismissedInterruptions = dismissedInterruptions }
    public var junitXML: String {
        let safeError = (error ?? "").replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        let failure = success ? "" : "<failure message=\"\(safeError)\">Step \(failedStep ?? 0) of \(totalSteps)</failure>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><testsuite name=\"CuyScout replay\" tests=\"1\" failures=\"\(success ? 0 : 1)\" time=\"\(Double(durationMilliseconds) / 1000)\"><testcase name=\"recorded exploration\" time=\"\(Double(durationMilliseconds) / 1000)\">\(failure)</testcase></testsuite>"
    }
}

public struct BatchStepResult: Codable, Sendable, Equatable {
    public let index: Int
    public let success: Bool
    public let durationMilliseconds: Int
    public let error: String?
    public let category: String?
    public let resultBase64: String?
    public init(index: Int, success: Bool, durationMilliseconds: Int, error: String? = nil, category: String? = nil, resultBase64: String? = nil) {
        self.index = index; self.success = success; self.durationMilliseconds = durationMilliseconds; self.error = error; self.category = category; self.resultBase64 = resultBase64
    }
}

public struct BatchExecutionResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let executed: Int
    public let total: Int
    public let steps: [BatchStepResult]
    public init(success: Bool, executed: Int, total: Int, steps: [BatchStepResult]) { self.success = success; self.executed = executed; self.total = total; self.steps = steps }
}

public struct BatchCompactSummary: Codable, Sendable, Equatable {
    public let requestID: String?
    public let success: Bool
    public let executed: Int
    public let total: Int
    public let failedSteps: [Int]
    public let failureCategories: [String: Int]
    public let retryableFailureCount: Int
    public let nextActionHint: String?
    public init(requestID: String? = nil, success: Bool, executed: Int, total: Int, failedSteps: [Int], failureCategories: [String: Int], retryableFailureCount: Int, nextActionHint: String?) { self.requestID = requestID; self.success = success; self.executed = executed; self.total = total; self.failedSteps = failedSteps; self.failureCategories = failureCategories; self.retryableFailureCount = retryableFailureCount; self.nextActionHint = nextActionHint }
}

public struct BatchValidation: Codable, Sendable, Equatable {
    public let valid: Bool
    public let actionCount: Int
    public let errors: [String]
    public let warnings: [String]
    public init(valid: Bool, actionCount: Int, errors: [String], warnings: [String]) { self.valid = valid; self.actionCount = actionCount; self.errors = errors; self.warnings = warnings }
}

public struct SelectorRepair: Codable, Sendable, Equatable {
    public let selector: ScoutSelector
    public let score: Double
    public let reason: String
    public init(selector: ScoutSelector, score: Double, reason: String) { self.selector = selector; self.score = score; self.reason = reason }
}

public struct ActionRepairProposal: Codable, Sendable, Equatable {
    public let original: ScoutAction
    public let proposed: ScoutAction
    public let score: Double
    public let reason: String
    public let requiresApproval: Bool
    public init(original: ScoutAction, proposed: ScoutAction, score: Double, reason: String, requiresApproval: Bool = true) { self.original = original; self.proposed = proposed; self.score = score; self.reason = reason; self.requiresApproval = requiresApproval }
}

public struct RepairAuditEntry: Codable, Sendable, Equatable {
    public enum Decision: String, Codable, Sendable { case proposed, applied, rejected }
    public let id: Int
    public let timestamp: Date
    public let sessionID: String
    public let proposal: ActionRepairProposal
    public let decision: Decision
    public init(id: Int, timestamp: Date = Date(), sessionID: String, proposal: ActionRepairProposal, decision: Decision) { self.id = id; self.timestamp = timestamp; self.sessionID = sessionID; self.proposal = proposal; self.decision = decision }
}

public struct AccessibilityIssue: Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable { case warning, error }
    public let rule: String
    public let severity: Severity
    public let message: String
    public let identifier: String?
    public let label: String?
    public init(rule: String, severity: Severity, message: String, identifier: String? = nil, label: String? = nil) { self.rule = rule; self.severity = severity; self.message = message; self.identifier = identifier; self.label = label }
}

public struct AccessibilityAudit: Codable, Sendable, Equatable {
    public let scannedElements: Int
    public let issues: [AccessibilityIssue]
    public init(scannedElements: Int, issues: [AccessibilityIssue]) { self.scannedElements = scannedElements; self.issues = issues }
}

public struct SessionDiagnosticReport: Codable, Sendable, Equatable {
    public let sessionID: String
    public let context: String
    public let url: String
    public let title: String?
    public let bridge: BridgeStatus
    public let webView: WebViewStatus
    public let navigation: NavigationGraph
    public let checkpoints: [ExplorationCheckpoint]
    public let recordedStepCount: Int
    public let accessibilityIssueCount: Int?
    public let metrics: SessionMetrics
    public init(sessionID: String, context: String, url: String, title: String?, bridge: BridgeStatus, webView: WebViewStatus, navigation: NavigationGraph, checkpoints: [ExplorationCheckpoint], recordedStepCount: Int, accessibilityIssueCount: Int?, metrics: SessionMetrics) { self.sessionID = sessionID; self.context = context; self.url = url; self.title = title; self.bridge = bridge; self.webView = webView; self.navigation = navigation; self.checkpoints = checkpoints; self.recordedStepCount = recordedStepCount; self.accessibilityIssueCount = accessibilityIssueCount; self.metrics = metrics }
}

public struct SessionMetrics: Codable, Sendable, Equatable {
    public let totalCommands: Int
    public let successfulCommands: Int
    public let failedCommands: Int
    public let failureRate: Double
    public let averageDurationMilliseconds: Double
    public let p95DurationMilliseconds: Int
    public let commandCounts: [String: Int]

    public init(totalCommands: Int, successfulCommands: Int, failedCommands: Int, failureRate: Double, averageDurationMilliseconds: Double, p95DurationMilliseconds: Int, commandCounts: [String: Int]) {
        self.totalCommands = totalCommands
        self.successfulCommands = successfulCommands
        self.failedCommands = failedCommands
        self.failureRate = failureRate
        self.averageDurationMilliseconds = averageDurationMilliseconds
        self.p95DurationMilliseconds = p95DurationMilliseconds
        self.commandCounts = commandCounts
    }
}

public struct FleetMetrics: Codable, Sendable, Equatable {
    public let activeSessions: Int
    public let retainedEvents: Int
    public let failedCommands: Int
    public let failureRate: Double
    public let averageDurationMilliseconds: Double
    public init(activeSessions: Int, retainedEvents: Int, failedCommands: Int, failureRate: Double, averageDurationMilliseconds: Double) { self.activeSessions = activeSessions; self.retainedEvents = retainedEvents; self.failedCommands = failedCommands; self.failureRate = failureRate; self.averageDurationMilliseconds = averageDurationMilliseconds }
}

public enum SessionPriority: String, Codable, Sendable, Equatable, Comparable {
    case low, normal, high, urgent
    public static func < (lhs: SessionPriority, rhs: SessionPriority) -> Bool {
        let order: [SessionPriority] = [.low, .normal, .high, .urgent]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public struct QueueEntry: Codable, Sendable, Equatable {
    public let sessionID: String
    public let deviceID: String?
    public let bundleIdentifier: String?
    public let driverID: String
    public let priority: SessionPriority
    public let enqueuedAt: Date
    public init(sessionID: String, deviceID: String?, bundleIdentifier: String?, driverID: String, priority: SessionPriority = .normal, enqueuedAt: Date = Date()) { self.sessionID = sessionID; self.deviceID = deviceID; self.bundleIdentifier = bundleIdentifier; self.driverID = driverID; self.priority = priority; self.enqueuedAt = enqueuedAt }
}

public struct FleetDashboard: Codable, Sendable, Equatable {
    public let activeSessions: Int
    public let queuedSessions: Int
    public let leasedDevices: Int
    public let availableDevices: Int
    public let totalEvents: Int
    public let failureRate: Double
    public let averageDurationMilliseconds: Double
    public let leases: [SchedulerLease]
    public let queue: [QueueEntry]
    public let workersOnline: Int
    public let workersExpired: Int
    public init(activeSessions: Int, queuedSessions: Int, leasedDevices: Int, availableDevices: Int, totalEvents: Int, failureRate: Double, averageDurationMilliseconds: Double, leases: [SchedulerLease], queue: [QueueEntry], workersOnline: Int = 0, workersExpired: Int = 0) { self.activeSessions = activeSessions; self.queuedSessions = queuedSessions; self.leasedDevices = leasedDevices; self.availableDevices = availableDevices; self.totalEvents = totalEvents; self.failureRate = failureRate; self.averageDurationMilliseconds = averageDurationMilliseconds; self.leases = leases; self.queue = queue; self.workersOnline = workersOnline; self.workersExpired = workersExpired }
}

public enum FarmWorkerStatus: String, Codable, Sendable, Equatable { case online, expired }

/// Worker remoto de device farm registrado en el gateway. El TTL se renueva
/// con cada heartbeat; sin señal el worker queda `expired` y deja de recibir
/// sesiones hasta reactivarse.
public struct FarmWorker: Codable, Sendable, Equatable {
    public let id: String
    public let url: String
    public let capabilities: [String]
    public let maxSessions: Int
    public var activeSessions: Int
    public let registeredAt: Date
    public var lastHeartbeat: Date
    public let ttlSeconds: Int
    public var status: FarmWorkerStatus
    public var capacityAvailable: Bool
    public init(id: String, url: String, capabilities: [String], maxSessions: Int, activeSessions: Int, registeredAt: Date = Date(), lastHeartbeat: Date = Date(), ttlSeconds: Int, status: FarmWorkerStatus = .online, capacityAvailable: Bool = true) { self.id = id; self.url = url; self.capabilities = capabilities; self.maxSessions = maxSessions; self.activeSessions = activeSessions; self.registeredAt = registeredAt; self.lastHeartbeat = lastHeartbeat; self.ttlSeconds = ttlSeconds; self.status = status; self.capacityAvailable = capacityAvailable }
}

public struct ConsoleLogEntry: Codable, Sendable, Equatable {
    public let id: Int
    public let timestamp: Date
    public let level: String
    public let message: String
    public let source: String?
    public init(id: Int, timestamp: Date = Date(), level: String, message: String, source: String? = nil) { self.id = id; self.timestamp = timestamp; self.level = level; self.message = message; self.source = source }
}

public struct ReactiveRule: Codable, Sendable, Equatable {
    public let id: String
    public let eventKind: String
    public let action: ScoutAction
    public let captureScreenshot: Bool
    public let enabled: Bool
    public init(id: String, eventKind: String, action: ScoutAction, captureScreenshot: Bool = false, enabled: Bool = true) { self.id = id; self.eventKind = eventKind; self.action = action; self.captureScreenshot = captureScreenshot; self.enabled = enabled }
}

public struct AppCacheEntry: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let path: String
    public let cachedAt: Date
    public let lastUsed: Date
    public init(bundleIdentifier: String, path: String, cachedAt: Date = Date(), lastUsed: Date = Date()) { self.bundleIdentifier = bundleIdentifier; self.path = path; self.cachedAt = cachedAt; self.lastUsed = lastUsed }
}

public struct SemanticFingerprint: Codable, Sendable, Equatable {
    public let elementID: String
    public let identifier: String
    public let label: String
    public let elementType: String
    public let frame: [String: Double]
    public let fingerprintHash: String
    public init(elementID: String, identifier: String, label: String, elementType: String, frame: [String: Double], fingerprintHash: String) { self.elementID = elementID; self.identifier = identifier; self.label = label; self.elementType = elementType; self.frame = frame; self.fingerprintHash = fingerprintHash }
}

public struct BehaviorComparison: Codable, Sendable, Equatable {
    public let matched: Bool
    public let differences: [String]
    public let expectedSuccess: Bool
    public let actualSuccess: Bool
    public init(matched: Bool, differences: [String], expectedSuccess: Bool, actualSuccess: Bool) { self.matched = matched; self.differences = differences; self.expectedSuccess = expectedSuccess; self.actualSuccess = actualSuccess }
}

public struct PluginRoute: Codable, Sendable, Equatable {
    public let pluginID: String
    public let method: String
    public let path: String
    public let description: String
    public init(pluginID: String, method: String, path: String, description: String) { self.pluginID = pluginID; self.method = method; self.path = path; self.description = description }
}

public struct DriverManifest: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let platforms: [String]
    public let libraryPath: String
    public let principalClass: String?
    public init(id: String, name: String, version: String, platforms: [String], libraryPath: String, principalClass: String? = nil) { self.id = id; self.name = name; self.version = version; self.platforms = platforms; self.libraryPath = libraryPath; self.principalClass = principalClass }
}

public struct DriverLoadResult: Codable, Sendable, Equatable {
    public let loaded: Bool
    public let driverID: String
    public let error: String?
    public init(loaded: Bool, driverID: String, error: String? = nil) { self.loaded = loaded; self.driverID = driverID; self.error = error }
}

public struct NetworkRequestEntry: Codable, Sendable, Equatable {
    public let id: Int
    public let timestamp: Date
    public let method: String
    public let url: String
    public let status: Int
    public let requestSize: Int
    public let responseSize: Int
    public let durationMilliseconds: Int
    public init(id: Int, timestamp: Date = Date(), method: String, url: String, status: Int = 0, requestSize: Int = 0, responseSize: Int = 0, durationMilliseconds: Int = 0) { self.id = id; self.timestamp = timestamp; self.method = method; self.url = url; self.status = status; self.requestSize = requestSize; self.responseSize = responseSize; self.durationMilliseconds = durationMilliseconds }
}

public struct ShardConfig: Codable, Sendable, Equatable {
    public let shardIndex: Int
    public let shardCount: Int
    public init(shardIndex: Int, shardCount: Int) { self.shardIndex = shardIndex; self.shardCount = shardCount }
}

public struct OtelSpan: Codable, Sendable, Equatable {
    public let traceID: String
    public let spanID: String
    public let parentSpanID: String?
    public let name: String
    public let startTime: Date
    public let endTime: Date?
    public let attributes: [String: String]
    public init(traceID: String, spanID: String, parentSpanID: String? = nil, name: String, startTime: Date = Date(), endTime: Date? = nil, attributes: [String: String] = [:]) { self.traceID = traceID; self.spanID = spanID; self.parentSpanID = parentSpanID; self.name = name; self.startTime = startTime; self.endTime = endTime; self.attributes = attributes }
}

public struct AppInfo: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let name: String
    public let type: String
    public init(bundleIdentifier: String, name: String, type: String) { self.bundleIdentifier = bundleIdentifier; self.name = name; self.type = type }
}

public struct StatusBarConfig: Codable, Sendable, Equatable {
    public let time: String?
    public let dataNetwork: String?
    public let wifiMode: String?
    public let batteryLevel: Int?
    public let batteryState: String?
    public init(time: String? = nil, dataNetwork: String? = nil, wifiMode: String? = nil, batteryLevel: Int? = nil, batteryState: String? = nil) { self.time = time; self.dataNetwork = dataNetwork; self.wifiMode = wifiMode; self.batteryLevel = batteryLevel; self.batteryState = batteryState }
}

public struct VideoRecordingResult: Codable, Sendable, Equatable {
    public let path: String
    public let started: Bool
    public init(path: String, started: Bool) { self.path = path; self.started = started }
}

public struct PushNotificationPayload: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let payloadPath: String
    public let sent: Bool
    public init(bundleIdentifier: String, payloadPath: String, sent: Bool) { self.bundleIdentifier = bundleIdentifier; self.payloadPath = payloadPath; self.sent = sent }
}

public struct ContentSize: Codable, Sendable, Equatable {
    public let size: String
    public init(size: String) { self.size = size }
}

public struct ProcessSpawnResult: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let pid: Int
    public let output: String
    public init(bundleIdentifier: String, pid: Int, output: String) { self.bundleIdentifier = bundleIdentifier; self.pid = pid; self.output = output }
}

public struct ICloudSyncStatus: Codable, Sendable, Equatable {
    public let synced: Bool
    public let detail: String
    public init(synced: Bool, detail: String) { self.synced = synced; self.detail = detail }
}

public enum FailureCategory: String, Codable, Sendable, Equatable {
    case product, selector, synchronization, environment, data, infrastructure
}

public struct TestVerificationResult: Codable, Sendable, Equatable {
    public let compiled: Bool
    public let executed: Bool
    public let passed: Bool
    public let exportFormat: String
    public let error: String?
    public let durationMilliseconds: Int
    public init(compiled: Bool, executed: Bool, passed: Bool, exportFormat: String, error: String? = nil, durationMilliseconds: Int = 0) { self.compiled = compiled; self.executed = executed; self.passed = passed; self.exportFormat = exportFormat; self.error = error; self.durationMilliseconds = durationMilliseconds }
}

public struct AccessibilityOverlay: Codable, Sendable, Equatable {
    public let screenshotBase64: String
    public let elements: [OverlayElement]
    public init(screenshotBase64: String, elements: [OverlayElement]) { self.screenshotBase64 = screenshotBase64; self.elements = elements }
}

public struct OverlayElement: Codable, Sendable, Equatable {
    public let identifier: String
    public let label: String
    public let elementType: String
    public let frame: [String: Double]
    public init(identifier: String, label: String, elementType: String, frame: [String: Double]) { self.identifier = identifier; self.label = label; self.elementType = elementType; self.frame = frame }
}

public struct VisualRegionCompare: Codable, Sendable, Equatable {
    public let identical: Bool
    public let differenceRatio: Double
    public let region: [String: Double]
    public let pixelDifferences: Int
    public init(identical: Bool, differenceRatio: Double, region: [String: Double], pixelDifferences: Int) { self.identical = identical; self.differenceRatio = differenceRatio; self.region = region; self.pixelDifferences = pixelDifferences }
}

public struct PluginSecurityPolicy: Codable, Sendable, Equatable {
    public let requireSignature: Bool
    public let allowedCapabilities: [String]
    public let deniedActions: [String]
    public init(requireSignature: Bool = false, allowedCapabilities: [String] = [], deniedActions: [String] = []) { self.requireSignature = requireSignature; self.allowedCapabilities = allowedCapabilities; self.deniedActions = deniedActions }
}

public struct OCRResult: Codable, Sendable, Equatable {
    public let recognizedText: String
    public let confidence: Double
    public let observations: [OCRObservation]
    public init(recognizedText: String, confidence: Double, observations: [OCRObservation] = []) { self.recognizedText = recognizedText; self.confidence = confidence; self.observations = observations }
}

public struct OCRObservation: Codable, Sendable, Equatable {
    public let text: String
    public let confidence: Double
    public let boundingBox: [String: Double]
    public init(text: String, confidence: Double, boundingBox: [String: Double]) { self.text = text; self.confidence = confidence; self.boundingBox = boundingBox }
}

public struct RunnerBuildResult: Codable, Sendable, Equatable {
    public let built: Bool
    public let runnerPath: String?
    public let error: String?
    public let signed: Bool
    public init(built: Bool, runnerPath: String? = nil, error: String? = nil, signed: Bool = false) { self.built = built; self.runnerPath = runnerPath; self.error = error; self.signed = signed }
}

/// Instalador resuelto y dispositivo destino; la instalación ocurre tras adquirir el lease.
public struct InstallerInfo: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let deviceID: String
    public let appPath: String
    public init(bundleIdentifier: String, deviceID: String, appPath: String) { self.bundleIdentifier = bundleIdentifier; self.deviceID = deviceID; self.appPath = appPath }
}

public struct CycleDetectionResult: Codable, Sendable, Equatable {
    public let cyclesDetected: Int
    public let cycleStates: [String]
    public let hasCycle: Bool
    public let recommendation: String?
    public init(cyclesDetected: Int, cycleStates: [String], hasCycle: Bool, recommendation: String? = nil) { self.cyclesDetected = cyclesDetected; self.cycleStates = cycleStates; self.hasCycle = hasCycle; self.recommendation = recommendation }
}

public struct ConformanceSnapshot: Codable, Sendable, Equatable {
    public let protocolName: String
    public let protocolVersion: String
    public let implemented: [String]
    public let partial: [String]
    public let pendingIntegrations: [String]
    public let automatedTests: Int
    public init(protocolName: String, protocolVersion: String, implemented: [String], partial: [String], pendingIntegrations: [String], automatedTests: Int) { self.protocolName = protocolName; self.protocolVersion = protocolVersion; self.implemented = implemented; self.partial = partial; self.pendingIntegrations = pendingIntegrations; self.automatedTests = automatedTests }
}

public struct SessionArtifactBundle: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let exportedAt: Date
    public let session: Session
    public let events: [ScoutEvent]
    public let metrics: SessionMetrics
    public let checkpoints: [ExplorationCheckpoint]
    public let testPlan: TestPlan?
    public let recording: RecordedSession?
    public let currentURL: String?
    public let navigation: NavigationGraph?
    public let sensitiveDataRedacted: Bool?
    public let totalCommandCount: Int?
    public let securityPolicy: SecurityPolicy?
    public let auditEntries: [SecurityAuditEntry]?
    public let repairEntries: [RepairAuditEntry]?
    public let accessibilityAudit: AccessibilityAudit?

    public init(session: Session, events: [ScoutEvent], metrics: SessionMetrics, checkpoints: [ExplorationCheckpoint], testPlan: TestPlan?, recording: RecordedSession? = nil, currentURL: String? = nil, navigation: NavigationGraph? = nil, redactSensitiveData: Bool = false, totalCommandCount: Int? = nil, securityPolicy: SecurityPolicy? = nil, auditEntries: [SecurityAuditEntry]? = nil, repairEntries: [RepairAuditEntry]? = nil, accessibilityAudit: AccessibilityAudit? = nil) {
        self.schemaVersion = "cuyscout.session-artifact.v1"
        self.exportedAt = Date()
        self.session = session
        self.events = redactSensitiveData ? events.map { ScoutEvent(id: $0.id, timestamp: $0.timestamp, kind: $0.kind, action: Self.redact($0.action), success: $0.success, durationMilliseconds: $0.durationMilliseconds, error: $0.error) } : events
        self.metrics = metrics
        self.checkpoints = checkpoints
        self.testPlan = testPlan
        self.recording = redactSensitiveData ? recording.map { RecordedSession(sessionID: $0.sessionID, startedAt: $0.startedAt, stoppedAt: $0.stoppedAt, steps: $0.steps.map { RecordedStep(index: $0.index, action: Self.redact($0.action), startedAt: $0.startedAt, durationMilliseconds: $0.durationMilliseconds, success: $0.success, error: $0.error) }) } : recording
        self.currentURL = currentURL
        self.navigation = navigation
        self.sensitiveDataRedacted = redactSensitiveData
        self.totalCommandCount = totalCommandCount
        self.securityPolicy = securityPolicy
        self.auditEntries = auditEntries
        self.repairEntries = redactSensitiveData ? repairEntries?.map { entry in
            let proposal = entry.proposal
            let redacted = ActionRepairProposal(original: Self.redact(proposal.original), proposed: Self.redact(proposal.proposed), score: proposal.score, reason: proposal.reason, requiresApproval: proposal.requiresApproval)
            return RepairAuditEntry(id: entry.id, timestamp: entry.timestamp, sessionID: entry.sessionID, proposal: redacted, decision: entry.decision)
        } : repairEntries
        self.accessibilityAudit = accessibilityAudit
    }

    private static func redact(_ action: ScoutAction) -> ScoutAction { action.redactedSensitiveData() }
}

public struct ArtifactStoreStatus: Codable, Sendable, Equatable {
    public let available: Bool
    public let persistedCount: Int
    public let autosaveInterval: Int
    public let artifactRetention: Int
    public let totalBytes: Int
    public let latestSavedAt: Date?
    public init(available: Bool, persistedCount: Int, autosaveInterval: Int, totalBytes: Int = 0, latestSavedAt: Date? = nil, artifactRetention: Int = 0) { self.available = available; self.persistedCount = persistedCount; self.autosaveInterval = autosaveInterval; self.totalBytes = totalBytes; self.latestSavedAt = latestSavedAt; self.artifactRetention = artifactRetention }
}

public struct SimulatorStorageItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let runtime: String
    public let state: String
    public let dataBytes: Int64
    public init(id: String, name: String, runtime: String, state: String, dataBytes: Int64) {
        self.id = id; self.name = name; self.runtime = runtime; self.state = state; self.dataBytes = dataBytes
    }
}

public struct SecurityPolicy: Codable, Sendable, Equatable {
    public let allowLifecycle: Bool
    public let allowClipboard: Bool
    public let allowCoordinates: Bool
    public let allowExternalURLs: Bool
    public let maxCommandsPerSession: Int
    public let deniedActionTypes: [String]
    public init(allowLifecycle: Bool = true, allowClipboard: Bool = true, allowCoordinates: Bool = true, allowExternalURLs: Bool = true, maxCommandsPerSession: Int = 0, deniedActionTypes: [String] = []) { self.allowLifecycle = allowLifecycle; self.allowClipboard = allowClipboard; self.allowCoordinates = allowCoordinates; self.allowExternalURLs = allowExternalURLs; self.maxCommandsPerSession = maxCommandsPerSession; self.deniedActionTypes = deniedActionTypes }
    private enum CodingKeys: String, CodingKey { case allowLifecycle, allowClipboard, allowCoordinates, allowExternalURLs, maxCommandsPerSession, deniedActionTypes }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); allowLifecycle = try c.decodeIfPresent(Bool.self, forKey: .allowLifecycle) ?? true; allowClipboard = try c.decodeIfPresent(Bool.self, forKey: .allowClipboard) ?? true; allowCoordinates = try c.decodeIfPresent(Bool.self, forKey: .allowCoordinates) ?? true; allowExternalURLs = try c.decodeIfPresent(Bool.self, forKey: .allowExternalURLs) ?? true; maxCommandsPerSession = max(0, try c.decodeIfPresent(Int.self, forKey: .maxCommandsPerSession) ?? 0); deniedActionTypes = try c.decodeIfPresent([String].self, forKey: .deniedActionTypes) ?? [] }
}

public struct ScoutEvent: Codable, Sendable, Equatable {
    public let id: Int
    public let timestamp: Date
    public let kind: String
    public let action: ScoutAction
    public let success: Bool
    public let durationMilliseconds: Int
    public let error: String?
    public init(id: Int, timestamp: Date = Date(), kind: String, action: ScoutAction, success: Bool, durationMilliseconds: Int, error: String? = nil) { self.id = id; self.timestamp = timestamp; self.kind = kind; self.action = action; self.success = success; self.durationMilliseconds = durationMilliseconds; self.error = error }
}

public struct SecurityAuditEntry: Codable, Sendable, Equatable {
    public let id: Int
    public let timestamp: Date
    public let sessionID: String
    public let actionType: String
    public let allowed: Bool
    public let sensitive: Bool
    public let reason: String?
    public init(id: Int, timestamp: Date = Date(), sessionID: String, actionType: String, allowed: Bool, sensitive: Bool, reason: String? = nil) { self.id = id; self.timestamp = timestamp; self.sessionID = sessionID; self.actionType = actionType; self.allowed = allowed; self.sensitive = sensitive; self.reason = reason }
}

public struct BridgeStatus: Codable, Sendable, Equatable {
    public let registered: Bool
    /// `true` solo cuando el runner XCTest ya pidió su primer comando. El gateway registra
    /// el puente antes de lanzar `xcodebuild`, así que "registrado" no significa que haya
    /// alguien atendiendo: durante ese arranque toda acción se quedaría esperando.
    public let runnerAttached: Bool
    public let pendingCommands: Int
    public let lastActivity: Date?
    public init(registered: Bool, pendingCommands: Int, lastActivity: Date?, runnerAttached: Bool = false) { self.registered = registered; self.pendingCommands = pendingCommands; self.lastActivity = lastActivity; self.runnerAttached = runnerAttached }
}

public enum DeviceOrientation: String, Codable, Sendable { case portrait, portraitUpsideDown, landscapeLeft, landscapeRight }

public struct ScoutSelector: Codable, Sendable, Equatable {
    public enum Strategy: String, Codable, Sendable { case accessibilityIdentifier, label, value, type, predicate, cssSelector, xpath }
    public let strategy: Strategy
    public let value: String
    public init(strategy: Strategy, value: String) { self.strategy = strategy; self.value = value }
}

public struct AccessibilityOptions: Codable, Sendable, Equatable {
    public let visibleOnly: Bool
    public let interactiveOnly: Bool
    public let maxElements: Int?
    public let includeSystemAlerts: Bool
    /// Descarta los controles que XCTest no puede tocar (ocultos o tapados por otra vista):
    /// `observe` no debe ofrecer al agente algo que la persona no ve.
    public let hittableOnly: Bool
    public init(visibleOnly: Bool = true, interactiveOnly: Bool = true, maxElements: Int? = 100, includeSystemAlerts: Bool = false, hittableOnly: Bool = false) { self.visibleOnly = visibleOnly; self.interactiveOnly = interactiveOnly; self.maxElements = maxElements; self.includeSystemAlerts = includeSystemAlerts; self.hittableOnly = hittableOnly }
    /// Las claves omitidas toman el valor por defecto: un agente que solo quiere acotar
    /// `maxElements` no debería tener que repetir el resto de la estructura.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visibleOnly = try c.decodeIfPresent(Bool.self, forKey: .visibleOnly) ?? true
        interactiveOnly = try c.decodeIfPresent(Bool.self, forKey: .interactiveOnly) ?? true
        maxElements = try c.decodeIfPresent(Int.self, forKey: .maxElements)
        includeSystemAlerts = try c.decodeIfPresent(Bool.self, forKey: .includeSystemAlerts) ?? false
        hittableOnly = try c.decodeIfPresent(Bool.self, forKey: .hittableOnly) ?? false
    }
}

public struct RecordedStep: Codable, Sendable, Equatable {
    public let index: Int
    public let action: ScoutAction
    public let startedAt: Date
    public let durationMilliseconds: Int
    public let success: Bool
    public let error: String?
    public init(index: Int, action: ScoutAction, startedAt: Date, durationMilliseconds: Int, success: Bool, error: String? = nil) { self.index = index; self.action = action; self.startedAt = startedAt; self.durationMilliseconds = durationMilliseconds; self.success = success; self.error = error }
}

public struct RecordedSession: Codable, Sendable, Equatable {
    public let sessionID: String
    public let startedAt: Date
    public let stoppedAt: Date?
    public let steps: [RecordedStep]
    public let generatedXCTest: String
    public let generatedAppium: String
    public let generatedAppiumTypeScript: String
    public let generatedAppiumPython: String
    public let generatedAppiumJava: String
    public var generatedGherkin: String { Self.makeGherkin(steps: steps) }
    public var portableJSON: String { (try? String(data: JSONEncoder().encode(steps), encoding: .utf8)) ?? "[]" }
    public init(sessionID: String, startedAt: Date, stoppedAt: Date?, steps: [RecordedStep]) { self.sessionID = sessionID; self.startedAt = startedAt; self.stoppedAt = stoppedAt; self.steps = steps; self.generatedXCTest = Self.makeXCTest(steps: steps); self.generatedAppium = Self.makeAppium(steps: steps); self.generatedAppiumTypeScript = Self.makeAppiumTypeScript(steps: steps); self.generatedAppiumPython = Self.makeAppiumPython(steps: steps); self.generatedAppiumJava = Self.makeAppiumJava(steps: steps) }

    private static func makeGherkin(steps: [RecordedStep]) -> String {
        let body = steps.map { step -> String in
            switch step.action {
            case .tapElement(let selector): return "  When the agent taps \(selector.strategy.rawValue) \"\(selector.value)\""
            case .typeElement(let selector, let text): return "  When the agent types \"\(text)\" into \(selector.strategy.rawValue) \"\(selector.value)\""
            case .assertVisible(let selector): return "  Then \(selector.strategy.rawValue) \"\(selector.value)\" should be visible"
            case .assertText(let selector, let expected): return "  Then \(selector.strategy.rawValue) \"\(selector.value)\" should contain \"\(expected)\""
            case .waitFor(let selector, let timeout): return "  And the agent waits up to \(timeout) seconds for \(selector.value)"
            default: return "  And the agent executes \"\(String(describing: step.action))\""
            }
        }.joined(separator: "\n")
        return """
Feature: CuyScout recorded exploration

Scenario: Replay recorded flow
  Given the application is launched
\(body)
"""
    }

    private static func xctestStatements(for action: ScoutAction) -> String {
        switch action {
        case .tap(let x, let y): return "        app.coordinate(withNormalizedOffset: CGVector(dx: \(x), dy: \(y))).tap()"
        case .swipe(let fx, let fy, let tx, let ty, let duration): return "        app.coordinate(withNormalizedOffset: CGVector(dx: \(fx), dy: \(fy))).press(forDuration: \(duration), thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: \(tx), dy: \(ty))))"
        case .type(let text): return "        app.typeText(\(swiftString(text)))"
        case .tapElement(let selector): return "        try element(\(swiftString(selector.value)), strategy: \(swiftString(selector.strategy.rawValue))).tap()"
        case .typeElement(let selector, let text): return "        do { let field = try element(\(swiftString(selector.value)), strategy: \(swiftString(selector.strategy.rawValue))); field.tap(); field.typeText(\(swiftString(text))) }"
        case .waitFor(let selector, let timeout): return "        XCTAssertTrue(try element(\(swiftString(selector.value)), strategy: \(swiftString(selector.strategy.rawValue))).waitForExistence(timeout: \(timeout)))"
        case .assertVisible(let selector): return "        XCTAssertTrue(try element(\(swiftString(selector.value)), strategy: \(swiftString(selector.strategy.rawValue))).exists)"
        case .assertText(let selector, let expected): return "        XCTAssertEqual(try element(\(swiftString(selector.value)), strategy: \(swiftString(selector.strategy.rawValue))).label, \(swiftString(expected)))"
        case .sequence(let actions): return actions.map { xctestStatements(for: $0) }.joined(separator: "\n")
        case .launch, .terminate, .backgroundApp, .openURL, .navigateBack, .navigateForward, .refresh, .acceptAlert, .dismissAlert, .rotate, .getClipboard, .setClipboard, .screenshot, .accessibilityTree, .findElement, .findElements, .findElementFromElement, .findElementsFromElement, .accessibilityTreeWithOptions, .accessibilityDiff, .clearElement, .elementAttribute, .elementDisplayed, .elementEnabled, .elementRect, .elementScreenshot, .elementSelected, .elementName, .scroll, .alertText, .elementProperty, .activeElement, .grantPermission, .setBiometry, .setLocation, .visualDiff, .submit, .setAppearance, .setStatusBar, .startVideoRecording, .stopVideoRecording, .listApps, .resetKeychain, .deepLink, .pushNotification, .setContentSize, .addMedia, .spawnProcess, .icloudSync, .shake, .doubleTap, .longPress, .pinch, .enumerateFiles, .downloadFile, .uploadFile, .getAppContainer, .getConfig, .setConfig: return "        // Acción registrada: \(String(describing: action))"
        }
    }

    private static func makeXCTest(steps: [RecordedStep]) -> String {
        let body = steps.map { xctestStatements(for: $0.action) }.joined(separator: "\n")
        return """
import XCTest

final class CuyScoutRecordedTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: \"APP_BUNDLE_ID\")

    func testRecordedFlow() throws {
        app.launch()
\(body)
    }

    private func element(_ value: String, strategy: String) throws -> XCUIElement {
        let query = app.descendants(matching: .any)
        switch strategy {
        case "accessibilityIdentifier": return query.matching(identifier: value).firstMatch
        case "label": return query.matching(NSPredicate(format: "label == %@", value)).firstMatch
        case "value": return query.matching(NSPredicate(format: "value == %@", value)).firstMatch
        case "predicate": return query.matching(NSPredicate(format: value)).firstMatch
        default: throw NSError(domain: "CuyScoutExport", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported selector strategy: \\(strategy)"])
        }
    }
}
"""
    }

    private static func makeAppium(steps: [RecordedStep]) -> String {
        let body = steps.map { appiumStatements(for: $0.action) }.joined(separator: "\n")
        return """
import { remote } from 'webdriverio';
import { expect } from '@wdio/globals';

let driver;

async function find(value, strategy) {
    switch (strategy) {
        case 'accessibilityIdentifier': return driver.$('~' + value);
        case 'label': return driver.$(`//*[@label=\"${value}\"]`);
        case 'value': return driver.$(`//*[@value=\"${value}\"]`);
        case 'predicate': return driver.$('-ios predicate string:' + value);
        default: return driver.$(value);
    }
}

describe('CuyScout exploration', () => {
    before(async () => {
        driver = await remote({
            hostname: process.env.APPIUM_HOST || '127.0.0.1',
            port: Number(process.env.APPIUM_PORT || 4723),
            path: '/',
            capabilities: {
                platformName: 'iOS',
                'appium:automationName': 'XCUITest',
                'appium:deviceName': process.env.IOS_DEVICE_NAME || 'iPhone Simulator',
                'appium:udid': process.env.IOS_UDID,
                'appium:bundleId': process.env.IOS_BUNDLE_ID,
                'appium:noReset': true
            }
        });
    });

    after(async () => { if (driver) await driver.deleteSession(); });

    it('replays the CuyScout exploration', async () => {
\(body)
    });
});
"""
    }

    private static func makeAppiumTypeScript(steps: [RecordedStep]) -> String {
        TypeScriptReplayExporter.make(steps: steps)
    }

    private static func appiumStatements(for action: ScoutAction) -> String {
        switch action {
        case .tap(let x, let y): return "        await driver.touchAction({ action: 'tap', x: \(x), y: \(y) });"
        case .swipe(let fx, let fy, let tx, let ty, let duration): return "        await driver.touchAction([{ action: 'press', x: \(fx), y: \(fy) }, { action: 'wait', ms: \(Int(duration * 1000)) }, { action: 'moveTo', x: \(tx), y: \(ty) }, 'release']);"
        case .type(let text): return "        await driver.keys(\(jsString(text)));"
        case .tapElement(let selector): return "        await (await find(\(jsString(selector.value)), \(jsString(selector.strategy.rawValue)))).click();"
        case .typeElement(let selector, let text): return "        await (await find(\(jsString(selector.value)), \(jsString(selector.strategy.rawValue)))).setValue(\(jsString(text)));"
        case .waitFor(let selector, let timeout): return "        await (await find(\(jsString(selector.value)), \(jsString(selector.strategy.rawValue)))).waitForDisplayed({ timeout: \(Int(timeout * 1000)) });"
        case .assertVisible(let selector): return "        await expect(await find(\(jsString(selector.value)), \(jsString(selector.strategy.rawValue)))).toBeDisplayed();"
        case .assertText(let selector, let expected): return "        await expect(await find(\(jsString(selector.value)), \(jsString(selector.strategy.rawValue)))).toHaveText(\(jsString(expected)));"
        case .sequence(let actions): return actions.map { appiumStatements(for: $0) }.joined(separator: "\n")
        case .launch, .terminate, .backgroundApp, .openURL, .navigateBack, .navigateForward, .refresh, .acceptAlert, .dismissAlert, .rotate, .getClipboard, .setClipboard, .screenshot, .accessibilityTree, .findElement, .findElements, .findElementFromElement, .findElementsFromElement, .accessibilityTreeWithOptions, .accessibilityDiff, .clearElement, .elementAttribute, .elementDisplayed, .elementEnabled, .elementRect, .elementScreenshot, .elementSelected, .elementName, .scroll, .alertText, .elementProperty, .activeElement, .grantPermission, .setBiometry, .setLocation, .visualDiff, .submit, .setAppearance, .setStatusBar, .startVideoRecording, .stopVideoRecording, .listApps, .resetKeychain, .deepLink, .pushNotification, .setContentSize, .addMedia, .spawnProcess, .icloudSync, .shake, .doubleTap, .longPress, .pinch, .enumerateFiles, .downloadFile, .uploadFile, .getAppContainer, .getConfig, .setConfig: return "        // Acción registrada no traducida automáticamente: \(String(describing: action))"
        }
    }

    private static func jsString(_ value: String) -> String { "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n") + "'" }

    private static func makeAppiumPython(steps: [RecordedStep]) -> String {
        let body = steps.map { pythonStatements(for: $0.action) }.joined(separator: "\n")
        return """
import os
import unittest
from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

class CuyScoutExplorationTest(unittest.TestCase):
    def setUp(self):
        options = XCUITestOptions()
        options.load_capabilities({
            "platformName": "iOS",
            "appium:automationName": "XCUITest",
            "appium:deviceName": os.getenv("IOS_DEVICE_NAME", "iPhone Simulator"),
            "appium:udid": os.getenv("IOS_UDID"),
            "appium:bundleId": os.getenv("IOS_BUNDLE_ID"),
            "appium:noReset": True
        })
        self.driver = webdriver.Remote(command_executor=f"http://{os.getenv('APPIUM_HOST', '127.0.0.1')}:{os.getenv('APPIUM_PORT', '4723')}", options=options)

    def tearDown(self):
        if getattr(self, "driver", None): self.driver.quit()

    def find(self, value, strategy):
        if strategy == "accessibilityIdentifier": return self.driver.find_element(AppiumBy.ACCESSIBILITY_ID, value)
        if strategy == "label": return self.driver.find_element(AppiumBy.IOS_PREDICATE, f"label == '{value}'")
        if strategy == "value": return self.driver.find_element(AppiumBy.IOS_PREDICATE, f"value == '{value}'")
        if strategy == "predicate": return self.driver.find_element(AppiumBy.IOS_PREDICATE, value)
        return self.driver.find_element(AppiumBy.XPATH, value)

    def test_recorded_exploration(self):
\(body)

if __name__ == "__main__": unittest.main()
"""
    }

    private static func pythonStatements(for action: ScoutAction) -> String {
        switch action {
        case .tap(let x, let y): return "        self.driver.execute_script(\"mobile: tap\", {\"x\": \(x), \"y\": \(y)})"
        case .swipe(let fx, let fy, let tx, let ty, let duration): return "        self.driver.execute_script(\"mobile: dragFromToForDuration\", {\"duration\": \(duration), \"fromX\": \(fx), \"fromY\": \(fy), \"toX\": \(tx), \"toY\": \(ty)})"
        case .type(let text): return "        self.driver.switch_to.active_element.send_keys(\(pythonString(text)))"
        case .tapElement(let selector): return "        self.find(\(pythonString(selector.value)), \(pythonString(selector.strategy.rawValue))).click()"
        case .typeElement(let selector, let text): return "        self.find(\(pythonString(selector.value)), \(pythonString(selector.strategy.rawValue))).send_keys(\(pythonString(text)))"
        case .waitFor(let selector, let timeout): return "        WebDriverWait(self.driver, \(timeout)).until(EC.visibility_of(self.find(\(pythonString(selector.value)), \(pythonString(selector.strategy.rawValue)))))"
        case .assertVisible(let selector): return "        self.assertTrue(self.find(\(pythonString(selector.value)), \(pythonString(selector.strategy.rawValue))).is_displayed())"
        case .assertText(let selector, let expected): return "        self.assertEqual(self.find(\(pythonString(selector.value)), \(pythonString(selector.strategy.rawValue))).text, \(pythonString(expected)))"
        case .sequence(let actions): return actions.map { pythonStatements(for: $0) }.joined(separator: "\n")
        case .launch, .terminate, .backgroundApp, .openURL, .navigateBack, .navigateForward, .refresh, .acceptAlert, .dismissAlert, .rotate, .getClipboard, .setClipboard, .screenshot, .accessibilityTree, .findElement, .findElements, .findElementFromElement, .findElementsFromElement, .accessibilityTreeWithOptions, .accessibilityDiff, .clearElement, .elementAttribute, .elementDisplayed, .elementEnabled, .elementRect, .elementScreenshot, .elementSelected, .elementName, .scroll, .alertText, .elementProperty, .activeElement, .grantPermission, .setBiometry, .setLocation, .visualDiff, .submit, .setAppearance, .setStatusBar, .startVideoRecording, .stopVideoRecording, .listApps, .resetKeychain, .deepLink, .pushNotification, .setContentSize, .addMedia, .spawnProcess, .icloudSync, .shake, .doubleTap, .longPress, .pinch, .enumerateFiles, .downloadFile, .uploadFile, .getAppContainer, .getConfig, .setConfig: return "        # Acción registrada no traducida automáticamente: \(String(describing: action))"
        }
    }

    private static func pythonString(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\"" }

    private static func makeAppiumJava(steps: [RecordedStep]) -> String {
        let body = steps.map { javaStatements(for: $0.action) }.joined(separator: "\n")
        return """
import io.appium.java_client.AppiumBy;
import io.appium.java_client.ios.IOSDriver;
import org.junit.jupiter.api.*;
import org.openqa.selenium.WebElement;
import java.net.URL;
import java.time.Duration;

class CuyScoutExplorationTest {
    private IOSDriver driver;

    @BeforeEach void setUp() throws Exception {
        var options = new io.appium.java_client.ios.options.XCUITestOptions();
        options.setDeviceName(System.getenv().getOrDefault("IOS_DEVICE_NAME", "iPhone Simulator"));
        options.setUdid(System.getenv("IOS_UDID"));
        options.setBundleId(System.getenv("IOS_BUNDLE_ID"));
        options.setNoReset(true);
        driver = new IOSDriver(new URL("http://" + System.getenv().getOrDefault("APPIUM_HOST", "127.0.0.1") + ":" + System.getenv().getOrDefault("APPIUM_PORT", "4723")), options);
    }
    @AfterEach void tearDown() { if (driver != null) driver.quit(); }
    @Test void replayCuyScoutExploration() {
\(body)
    }
    private WebElement find(String value, String strategy) {
        return switch (strategy) {
            case "accessibilityIdentifier" -> driver.findElement(AppiumBy.accessibilityId(value));
            case "label" -> driver.findElement(AppiumBy.iOSNsPredicateString("label == '" + value.replace("'", "\\'") + "'"));
            case "value" -> driver.findElement(AppiumBy.iOSNsPredicateString("value == '" + value.replace("'", "\\'") + "'"));
            case "predicate" -> driver.findElement(AppiumBy.iOSNsPredicateString(value));
            default -> driver.findElement(AppiumBy.cssSelector(value));
        };
    }
}
"""
    }

    private static func javaStatements(for action: ScoutAction) -> String {
        switch action {
        case .type(let text): return "        driver.getKeyboard().sendKeys(\(javaString(text)));"
        case .tapElement(let selector): return "        find(\(javaString(selector.value)), \(javaString(selector.strategy.rawValue))).click();"
        case .typeElement(let selector, let text): return "        find(\(javaString(selector.value)), \(javaString(selector.strategy.rawValue))).sendKeys(\(javaString(text)));"
        case .clearElement(let selector): return "        find(\(javaString(selector.value)), \(javaString(selector.strategy.rawValue))).clear();"
        case .waitFor(let selector, let timeout): return "        new org.openqa.selenium.support.ui.WebDriverWait(driver, Duration.ofMillis(\(Int(timeout * 1000)))).until(d -> find(\(javaString(selector.value)), \(javaString(selector.strategy.rawValue))).isDisplayed());"
        case .assertVisible(let selector): return "        Assertions.assertTrue(find(\(javaString(selector.value)), \(javaString(selector.strategy.rawValue))).isDisplayed());"
        case .assertText(let selector, let expected): return "        Assertions.assertTrue(find(\(javaString(selector.value)), \(javaString(selector.strategy.rawValue))).getText().contains(\(javaString(expected))));"
        case .sequence(let actions): return actions.map { javaStatements(for: $0) }.joined(separator: "\n")
        default: return "        // Acción registrada no traducida automáticamente: \(String(describing: action))"
        }
    }

    private static func javaString(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\"" }

    private static func swiftString(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\"" }
}

public struct ExplorationLimits: Codable, Sendable, Equatable {
    public let maxActions: Int
    public let maxStateRepeats: Int
    public let maxActionRepeats: Int
    public let timeoutSeconds: Double
    public init(maxActions: Int = 100, maxStateRepeats: Int = 3, maxActionRepeats: Int = 4, timeoutSeconds: Double = 600) { self.maxActions = maxActions; self.maxStateRepeats = maxStateRepeats; self.maxActionRepeats = maxActionRepeats; self.timeoutSeconds = timeoutSeconds }
}

public struct ExplorationReport: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case running, completed, loopDetected, actionLimitReached, timeout }
    public let status: Status
    public let reason: String?
    public let actionCount: Int
    public let repeatedStateCount: Int
    public let visitedStateCount: Int
    public let suggestion: String?
    public init(status: Status, reason: String? = nil, actionCount: Int, repeatedStateCount: Int, visitedStateCount: Int, suggestion: String? = nil) { self.status = status; self.reason = reason; self.actionCount = actionCount; self.repeatedStateCount = repeatedStateCount; self.visitedStateCount = visitedStateCount; self.suggestion = suggestion }
}

public struct ExplorationResult: Codable, Sendable, Equatable {
    public let report: ExplorationReport
    public let recording: RecordedSession?
    public let accessibilityAudit: AccessibilityAudit?
    public init(report: ExplorationReport, recording: RecordedSession?, accessibilityAudit: AccessibilityAudit? = nil) { self.report = report; self.recording = recording; self.accessibilityAudit = accessibilityAudit }
}

public enum ScoutError: LocalizedError, Sendable { case invalidRequest(String); case sessionNotFound; case noSuchElement(String); case staleElementReference(String); case unsupported(String); case commandFailed(String); case message(String); case notInteractable(String)
    /// `LocalizedError` exige `String?`. Con un `String` no opcional Swift no satisface el
    /// requisito del protocolo: `localizedDescription` ignora este texto y devuelve el
    /// genérico "(CuyScoutCore.ScoutError error N.)", que es lo que acababa en las respuestas
    /// HTTP/MCP, los eventos y la clasificación de fallos.
    public var errorDescription: String? { switch self { case .invalidRequest(let s), .noSuchElement(let s), .staleElementReference(let s), .unsupported(let s), .commandFailed(let s), .message(let s), .notInteractable(let s): s; case .sessionNotFound: "Session not found" } }
    public var w3cCode: String { switch self { case .invalidRequest: "invalid argument"; case .sessionNotFound: "invalid session id"; case .noSuchElement: "no such element"; case .staleElementReference: "stale element reference"; case .unsupported: "unsupported command"; case .notInteractable: "element not interactable"; case .commandFailed, .message: "unknown error" } }
    public var httpStatus: Int { switch self { case .invalidRequest: 400; case .sessionNotFound, .noSuchElement, .staleElementReference: 404; case .unsupported: 501; case .notInteractable: 400; case .commandFailed, .message: 500 } }
    /// Siguiente paso recomendado para el agente; viaja como `hint` junto al error.
    public var hint: String? {
        switch self {
        case .notInteractable(let message) where message.contains("not_visible"):
            return "No reintentes: el elemento existe pero está oculto o tapado en la pantalla actual y no se tocó. Vuelve a observar y actúa solo sobre controles de observe.actions; si el campo aparece tras tocar una opción, tócala primero."
        case .notInteractable:
            return "No reintentes: no es un fallo técnico. Si el control abre la pantalla con el campo, tócalo (tapElement), vuelve a observar y escribe en el campo editable (textField/secureTextField)."
        case .noSuchElement:
            return "Vuelve a observar y usa un selector de la lista de acciones actual."
        case .sessionNotFound:
            return "La sesión no existe o ya se cerró: abre una nueva."
        case .invalidRequest(let message) where message.contains("session_lease_expired"):
            return "La sesión caducó por inactividad y no se puede recuperar: ciérrala (DELETE /session/:id) y abre una nueva. Envía heartbeat si vas a pasar más de 10 minutos sin comandos."
        case .invalidRequest(let message) where message.contains("xctest_runner_starting"):
            return "Espera a que readiness deje de reportar bloqueos antes de enviar acciones."
        case .commandFailed(let message) where message.contains("teclado"):
            return "El campo no mostró el teclado del sistema. Vuelve a observar antes de reintentar: puede que la pantalla haya cambiado o que el campo use un teclado propio de la app."
        default:
            return nil
        }
    }
}
