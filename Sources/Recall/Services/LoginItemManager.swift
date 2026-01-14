import ServiceManagement

class LoginItemManager {
    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        service.status == .enabled
    }

    func enable() throws {
        try service.register()
    }

    func disable() throws {
        try service.unregister()
    }

    func toggle() throws {
        if isEnabled {
            try disable()
        } else {
            try enable()
        }
    }
}
