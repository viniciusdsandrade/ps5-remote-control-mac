import Foundation

/// A Remote Play session. By default it runs in controller-only mode: audio and video disabled on
/// the client, so the library drops the stream packets as they arrive. Passing `videoSink` turns
/// the video on (audio stays off) and hands every sample to it, which the CLI uses to look at the
/// console's screen while testing. Events arrive on library threads.
final class PSSession {
    enum Event {
        case connected
        case loginPinRequest(pinIncorrect: Bool)
        case nickname(String)
        /// The console says what is on its screen can't be streamed (video apps, protected content):
        /// the picture on the TV is blacked out while the session is open. false = it can again.
        case cantDisplay(Bool)
        case quit(reason: ChiakiQuitReason, reasonText: String, detail: String?, isError: Bool)
        case other(ChiakiEventType)
    }

    private let session: UnsafeMutablePointer<ChiakiSession>
    private let log: ChiakiLogger
    private let lock = NSLock()
    private var started = false
    private var joined = false
    private var finished = false
    private let videoSink: ((Data) -> Void)?

    /// Called on a library thread. Never call stop() from inside it.
    var onEvent: ((Event) -> Void)?

    /// `dualSense` announces the client to the console as a DualSense, like the official chiaki-ng
    /// client always does on PS5; false announces a DualShock 4.
    init(host: PSHost, address: String? = nil, log: ChiakiLogger, dualSense: Bool = true,
         videoSink: ((Data) -> Void)? = nil) throws {
        ChiakiCore.ensureInitialized()
        self.log = log
        self.videoSink = videoSink
        guard let rpKey = host.rpKeyBytes else { throw ChiakiError.failed("RP-Key inválida no host.json") }

        session = .allocate(capacity: 1)
        session.initialize(to: ChiakiSession())

        var info = ChiakiConnectInfo()   // zeroed: no holepunch session, no rudp socket
        info.ps5 = true
        store(host.registKeyBytes, into: &info.regist_key)
        store(rpKey, into: &info.morning)
        if videoSink != nil {
            chiaki_connect_video_profile_preset(&info.video_profile, CHIAKI_VIDEO_RESOLUTION_PRESET_540p, CHIAKI_VIDEO_FPS_PRESET_30)
            info.audio_video_disabled = CHIAKI_AUDIO_DISABLED
        } else {
            chiaki_connect_video_profile_preset(&info.video_profile, CHIAKI_VIDEO_RESOLUTION_PRESET_360p, CHIAKI_VIDEO_FPS_PRESET_30)
            info.audio_video_disabled = CHIAKI_AUDIO_VIDEO_DISABLED
        }
        info.video_profile_auto_downgrade = true
        info.enable_keyboard = false
        info.enable_dualsense = dualSense
        info.auto_regist = false
        info.packet_loss_max = 0.05
        info.enable_idr_on_fec_failure = false
        if let account = host.accountIDBytes { store(account, into: &info.psn_account_id) }

        // chiaki_session_init resolves the host right away, so the C string only has to live here.
        let target = address ?? host.lastAddress
        let err = target.withCString { cHost -> ChiakiErrorCode in
            info.host = cHost
            return chiaki_session_init(session, &info, log.pointer)
        }
        if err != CHIAKI_ERR_SUCCESS {
            session.deinitialize(count: 1)
            session.deallocate()
            throw ChiakiError.code(err, "chiaki_session_init")
        }

        let user = Unmanaged.passUnretained(self).toOpaque()
        chiaki_session_set_event_cb(session, { eventPointer, user in
            guard let eventPointer, let user else { return }
            let me = Unmanaged<PSSession>.fromOpaque(user).takeUnretainedValue()
            me.handle(eventPointer.pointee)
        }, user)
        // The library calls this one without checking for NULL: when the console reports content that
        // can't be streamed, a missing sink crashes the process (seen with a streaming app on screen).
        var displaySink = ChiakiCtrlDisplaySink(user: user, cantdisplay_cb: { user, cantDisplay in
            guard let user else { return }
            let me = Unmanaged<PSSession>.fromOpaque(user).takeUnretainedValue()
            me.onEvent?(.cantDisplay(cantDisplay))
        })
        chiaki_session_ctrl_set_display_sink(session, &displaySink)
        // With video disabled this never fires; either way, accepting every sample keeps the receiver quiet.
        chiaki_session_set_video_sample_cb(session, { buffer, size, _, _, user in
            guard let user, let buffer else { return true }
            let me = Unmanaged<PSSession>.fromOpaque(user).takeUnretainedValue()
            me.videoSink?(Data(bytes: buffer, count: size))
            return true
        }, user)
    }

    deinit {
        stop()
        if !finished {
            chiaki_session_fini(session)
            finished = true
        }
        session.deinitialize(count: 1)
        session.deallocate()
    }

    func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        try chiakiCheck(chiaki_session_start(session), "chiaki_session_start")
        started = true
    }

    /// Asks the session to end and waits for its threads. Safe to call more than once.
    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard started, !joined else { return }
        chiaki_session_stop(session)
        chiaki_session_join(session)
        joined = true
    }

    func send(_ state: PadState) throws {
        var raw = state.raw
        try chiakiCheck(chiaki_session_set_controller_state(session, &raw), "chiaki_session_set_controller_state")
    }

    /// Puts the console in rest mode. Needs a connected session; the console then ends it.
    func gotoBed() throws {
        try chiakiCheck(chiaki_session_goto_bed(session), "chiaki_session_goto_bed")
    }

    /// The library's "go to home screen" control message (untested on PS5; holding PS is the fallback).
    func goHome() throws {
        try chiakiCheck(chiaki_session_go_home(session), "chiaki_session_go_home")
    }

    /// The console user's 4-digit login passcode, when the session asks for it.
    func setLoginPin(_ pin: String) throws {
        let digits = Array(pin.utf8)
        try chiakiCheck(chiaki_session_set_login_pin(session, digits, digits.count), "chiaki_session_set_login_pin")
    }

    private func handle(_ event: ChiakiEvent) {
        let mapped: Event
        switch event.type {
        case CHIAKI_EVENT_CONNECTED:
            mapped = .connected
        case CHIAKI_EVENT_LOGIN_PIN_REQUEST:
            mapped = .loginPinRequest(pinIncorrect: event.login_pin_request.pin_incorrect)
        case CHIAKI_EVENT_NICKNAME_RECEIVED:
            mapped = .nickname(cString(event.server_nickname))
        case CHIAKI_EVENT_QUIT:
            let reason = event.quit.reason
            let text = String(cString: chiaki_quit_reason_string(reason))
            let detail = event.quit.reason_str.map { String(cString: $0) }
            mapped = .quit(reason: reason, reasonText: text, detail: detail, isError: chiaki_quit_reason_is_error(reason))
        default:
            mapped = .other(event.type)
        }
        onEvent?(mapped)
    }
}
