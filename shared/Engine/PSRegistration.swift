import Foundation

/// Pairs with the console ("Emparelhar dispositivo" on the PS5): sends the 8-digit PIN and the PSN
/// account id, gets back the regist key and the RP key that every later session uses.
enum PSRegistration {
    private final class Waiter {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var eventType: ChiakiRegistEventType?
        var host: ChiakiRegisteredHost?
    }

    /// Blocking; takes a few seconds. `accountID` is the base64 PSN account id.
    static func pair(address: String, pin: UInt32, accountID: String, hostID: String?, systemVersion: String?,
                     log: ChiakiLogger, timeout: TimeInterval = 40) throws -> PSHost {
        ChiakiCore.ensureInitialized()
        guard let accountBytes = PSNAccountID.decode(accountID) else {
            throw ChiakiError.failed("ID da conta PSN inválido (esperado base64 de 8 bytes)")
        }

        let regist = UnsafeMutablePointer<ChiakiRegist>.allocate(capacity: 1)
        regist.initialize(to: ChiakiRegist())
        defer { regist.deinitialize(count: 1); regist.deallocate() }

        var info = ChiakiRegistInfo()   // zeroed: no PSN online id, no holepunch, no rudp
        info.target = CHIAKI_TARGET_PS5_1
        info.broadcast = false
        info.pin = pin
        info.console_pin = 0
        store(accountBytes, into: &info.psn_account_id)

        let waiter = Waiter()
        let user = Unmanaged.passUnretained(waiter).toOpaque()
        // chiaki_regist_start copies the host string, so the C string only has to live during the call.
        let err = address.withCString { cHost -> ChiakiErrorCode in
            info.host = cHost
            return chiaki_regist_start(regist, log.pointer, &info, { event, user in
                guard let event, let user else { return }
                let waiter = Unmanaged<Waiter>.fromOpaque(user).takeUnretainedValue()
                waiter.lock.lock()
                waiter.eventType = event.pointee.type
                if let host = event.pointee.registered_host { waiter.host = host.pointee }  // copy: lives on the regist thread
                waiter.lock.unlock()
                waiter.semaphore.signal()
            }, user)
        }
        try chiakiCheck(err, "chiaki_regist_start")

        let outcome = waiter.semaphore.wait(timeout: .now() + timeout)
        if outcome == .timedOut { chiaki_regist_stop(regist) }
        chiaki_regist_fini(regist)   // joins the thread
        guard outcome == .success else { throw ChiakiError.timeout("pareamento") }

        waiter.lock.lock()
        let type = waiter.eventType
        let registered = waiter.host
        waiter.lock.unlock()

        switch type {
        case CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS:
            guard let registered else { throw ChiakiError.failed("pareamento terminou sem dados do console") }
            return PSHost(registered: registered, address: address, accountID: accountID,
                          hostID: hostID, systemVersion: systemVersion)
        case CHIAKI_REGIST_EVENT_TYPE_FINISHED_CANCELED:
            throw ChiakiError.failed("pareamento cancelado")
        default:
            throw ChiakiError.failed("pareamento recusado pelo console (código errado, ID da conta errado ou Uso remoto em uso; veja o log acima)")
        }
    }
}
