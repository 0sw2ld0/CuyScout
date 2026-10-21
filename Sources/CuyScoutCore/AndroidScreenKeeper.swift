import Foundation

/// Mantiene encendida la pantalla de un Android mientras dura una sesión.
///
/// Un agente espera entre acción y acción; si la pantalla se apaga (el teléfono de pruebas suele tener 5 minutos) el runner
/// deja de poder tocar la app. Dos medidas:
/// - Al abrir la sesión se activa «pantalla encendida al cargar» (`stay_on_while_plugged_in`) y al cerrarla se devuelve el valor
///   que había. El valor original se guarda en el teléfono (`stayOnMarker`) para recuperarlo aunque CuyScout muera sin cerrar:
///   la siguiente sesión lo reconoce y no confunde el valor que dejamos nosotros con el de la persona.
/// - Cada `interval` se comprueba si la pantalla sigue despierta; si no, se despierta y se descarta el bloqueo simple (deslizar).
///   Un PIN, patrón o huella no se tocan nunca: la sesión informa `device_locked` y la persona lo desbloquea.
/// `CUYSCOUT_KEEP_AWAKE=0` desactiva todo esto.
final class AndroidScreenKeeper: @unchecked Sendable {
    private let controller: AndroidController
    private let device: Device
    private let interval: TimeInterval
    private let lock = NSLock()
    private let stopSignal = DispatchSemaphore(value: 0)
    private var locked = false
    private var running = false

    init(controller: AndroidController, device: Device, interval: TimeInterval = 20) {
        self.controller = controller; self.device = device; self.interval = interval
    }

    static func isEnabled(environment: [String: String]) -> Bool { environment["CUYSCOUT_KEEP_AWAKE"] != "0" }

    var isLocked: Bool { lock.lock(); defer { lock.unlock() }; return locked }

    func start() {
        lock.lock(); guard !running else { lock.unlock(); return }; running = true; lock.unlock()
        try? controller.keepScreenOn(on: device)
        wakeIfNeeded()
        Thread.detachNewThread { [weak self] in
            while let self {
                if self.stopSignal.wait(timeout: .now() + self.interval) == .success { return }
                self.wakeIfNeeded()
            }
        }
    }

    func stop() {
        lock.lock(); let wasRunning = running; running = false; lock.unlock()
        guard wasRunning else { return }
        stopSignal.signal()
        try? controller.restoreScreenTimeout(on: device)
    }

    /// Despierta la pantalla si está apagada y anota si queda un bloqueo que CuyScout no puede quitar.
    func wakeIfNeeded() {
        let state = (try? controller.wakefulness(on: device)) ?? ""
        if AndroidController.isAsleep(state) {
            try? controller.wakeUp(on: device)
            Thread.sleep(forTimeInterval: 0.5)
        }
        // Solo se mira el bloqueo si la pantalla estaba apagada o si ya se había visto bloqueada.
        let focus = (try? controller.focusedWindow(on: device)) ?? ""
        var stillLocked = AndroidController.isLockScreen(focus)
        if stillLocked {
            try? controller.dismissKeyguard(on: device)
            Thread.sleep(forTimeInterval: 0.5)
            stillLocked = AndroidController.isLockScreen((try? controller.focusedWindow(on: device)) ?? "")
        }
        lock.lock(); locked = stillLocked; lock.unlock()
    }
}
