import Foundation
import GameController
import os

/// Game controllers (D3, D17): buttons and the left stick become `ControllerButton`s,
/// looked up in the bindings and dispatched through `InputRouter`.
final class ControllerInput {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "ControllerInput")
    private static let repeatDelay = Duration.milliseconds(450)
    private static let repeatInterval = Duration.milliseconds(120)
    private static let directions: Set<RemoteCommand> = [.up, .down, .left, .right]

    private let inputRouter: InputRouter
    private let monitorInBackground: Bool
    private var observers: [NSObjectProtocol] = []
    private var repeatTask: Task<Void, Never>?
    private var repeatingButton: ControllerButton?
    private var stickDirection: RemoteCommand?

    init(inputRouter: InputRouter, monitorInBackground: Bool) {
        self.inputRouter = inputRouter
        self.monitorInBackground = monitorInBackground
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] notification in
            let name = (notification.object as? GCController).map(Self.describe) ?? "?"
            MainActor.assumeIsolated { self?.controllerDidConnect(name) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] notification in
            let name = (notification.object as? GCController).map(Self.describe) ?? "?"
            MainActor.assumeIsolated { self?.controllerDidDisconnect(name) }
        })
        for controller in GCController.controllers() {
            controllerDidConnect(Self.describe(controller))
        }
    }

    /// Also detaches every element handler (they'd keep dispatching otherwise) and background monitoring (L15).
    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GCController.controllers().forEach(unconfigure)
        GCController.shouldMonitorBackgroundEvents = false
        stopRepeat()
        stickDirection = nil
    }

    private nonisolated static func describe(_ controller: GCController) -> String {
        let profile = controller.extendedGamepad != nil ? "extendedGamepad"
            : controller.microGamepad != nil ? "microGamepad" : "other"
        return "\(controller.vendorName ?? "Unknown") (\(profile))"
    }

    private func controllerDidConnect(_ name: String) {
        Self.logger.info("Controller connected: \(name, privacy: .public)")
        // L4: only after a controller connected, never before (SDL found an MFi crash otherwise).
        if monitorInBackground {
            GCController.shouldMonitorBackgroundEvents = true
        }
        // Reconfiguring a controller only replaces its handlers, so configure all of them.
        GCController.controllers().forEach(configure)
    }

    private func controllerDidDisconnect(_ name: String) {
        Self.logger.info("Controller disconnected: \(name, privacy: .public)")
        stopRepeat()
        stickDirection = nil
    }

    private func configure(_ controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            bind(gamepad.dpad.up, to: .dpadUp)
            bind(gamepad.dpad.down, to: .dpadDown)
            bind(gamepad.dpad.left, to: .dpadLeft)
            bind(gamepad.dpad.right, to: .dpadRight)
            bind(gamepad.buttonA, to: .a)
            bind(gamepad.buttonB, to: .b)
            bind(gamepad.buttonX, to: .x)
            bind(gamepad.buttonY, to: .y)
            bind(gamepad.leftShoulder, to: .leftShoulder)
            bind(gamepad.rightShoulder, to: .rightShoulder)
            bind(gamepad.buttonMenu, to: .menu)
            bind(gamepad.leftTrigger, to: .leftTrigger)
            bind(gamepad.rightTrigger, to: .rightTrigger)
            if let buttonOptions = gamepad.buttonOptions {
                bind(buttonOptions, to: .options)
            }
            if let buttonHome = gamepad.buttonHome {
                // macOS 26 opens the Game Overlay on Home otherwise.
                buttonHome.preferredSystemGestureState = .disabled
                bind(buttonHome, to: .home)
            }
            gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
                MainActor.assumeIsolated { self?.stickChanged(x: x, y: y) }
            }
        } else if let gamepad = controller.microGamepad {
            gamepad.reportsAbsoluteDpadValues = false
            bind(gamepad.dpad.up, to: .dpadUp)
            bind(gamepad.dpad.down, to: .dpadDown)
            bind(gamepad.dpad.left, to: .dpadLeft)
            bind(gamepad.dpad.right, to: .dpadRight)
            bind(gamepad.buttonA, to: .a)
            bind(gamepad.buttonX, to: .x)
            bind(gamepad.buttonMenu, to: .menu)
        }
    }

    /// Clears exactly the handlers `configure` sets.
    private func unconfigure(_ controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            let buttons: [GCControllerButtonInput?] = [
                gamepad.dpad.up, gamepad.dpad.down, gamepad.dpad.left, gamepad.dpad.right,
                gamepad.buttonA, gamepad.buttonB, gamepad.buttonX, gamepad.buttonY,
                gamepad.leftShoulder, gamepad.rightShoulder, gamepad.buttonMenu,
                gamepad.buttonOptions, gamepad.buttonHome, gamepad.leftTrigger, gamepad.rightTrigger,
            ]
            buttons.forEach { $0?.pressedChangedHandler = nil }
            gamepad.leftThumbstick.valueChangedHandler = nil
        } else if let gamepad = controller.microGamepad {
            let buttons: [GCControllerButtonInput] = [
                gamepad.dpad.up, gamepad.dpad.down, gamepad.dpad.left, gamepad.dpad.right,
                gamepad.buttonA, gamepad.buttonX, gamepad.buttonMenu,
            ]
            buttons.forEach { $0.pressedChangedHandler = nil }
        }
    }

    private func bind(_ input: GCControllerButtonInput, to button: ControllerButton) {
        input.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.buttonChanged(button, pressed: pressed) }
        }
    }

    private func buttonChanged(_ button: ControllerButton, pressed: Bool) {
        guard pressed else {
            if repeatingButton == button { stopRepeat() }
            return
        }
        stopRepeat()
        // M7 L8: learning a button.
        if inputRouter.capture(.controller(button: button)) { return }
        guard let binding = inputRouter.bindings.binding(controller: button) else { return }
        inputRouter.dispatch(binding.command, isGlobal: binding.isGlobal)
        if Self.directions.contains(binding.command) {
            startRepeat(button: button, binding: binding)
        }
    }

    /// The left stick feeds the D-pad path, so it repeats the same way.
    private func stickChanged(x: Float, y: Float) {
        let direction = ThumbstickDirection.resolve(x: x, y: y, current: stickDirection)
        guard direction != stickDirection else { return }
        if let old = stickDirection {
            buttonChanged(Self.dpadButton(for: old), pressed: false)
        }
        stickDirection = direction
        if let direction {
            buttonChanged(Self.dpadButton(for: direction), pressed: true)
        }
    }

    private static func dpadButton(for direction: RemoteCommand) -> ControllerButton {
        switch direction {
        case .up: .dpadUp
        case .down: .dpadDown
        case .left: .dpadLeft
        default: .dpadRight
        }
    }

    private func startRepeat(button: ControllerButton, binding: InputBinding) {
        repeatingButton = button
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.repeatDelay)
                while true {
                    self?.inputRouter.dispatch(binding.command, isGlobal: binding.isGlobal)
                    try await Task.sleep(for: Self.repeatInterval)
                }
            } catch {
                // Cancelled: the button was released.
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        repeatingButton = nil
    }
}
