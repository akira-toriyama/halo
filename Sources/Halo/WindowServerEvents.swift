// WindowServerEvents.swift — the private-SkyLight window-event seam.
//
// Delivers window MOVE / RESIZE / REORDER / FRONT-change events at
// ~5ms (median 4-6ms, no long tail), which is what lets the border hug
// a window smoothly while you drag it.
//
// THE NON-OBVIOUS PART (verified empirically before this code existed):
// you CANNOT receive these on the process's MAIN SkyLight connection
// from an AppKit app — AppKit owns and services it, and notify procs
// registered there deliver nothing (even with the event-port drain
// pump). The working topology, the one yabai / sketchybar / JankyBorders
// all converge on, is a DEDICATED connection (SLSNewConnection) that we
// register on and drain ourselves:
//
//   1. cid = SLSNewConnection(0)              — our own connection
//   2. SLSRegisterConnectionNotifyProc(cid, …) for each event code
//   3. SLSRequestNotificationsForWindows(cid, …) — per-window MOVE/RESIZE
//      (a FULL-REPLACE set; re-issue whenever the window set changes)
//   4. SLSGetEventPort(cid) → CFMachPort → CFRunLoopAddSource(main)
//   5. the CFMachPort callback DRAINS via SLEventCreateNextEvent — and
//      that drain is what dispatches the registered notify procs.
//
// All read/observe-only — SIP-on safe, never mutates a window. These
// private symbols are dlsym-bound (no public headers); a missing symbol
// degrades to "unavailable" rather than crashing.

import AppKit
import CoreFoundation
import Darwin

private let slHandle =
    dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

private func slSym(_ name: String) -> UnsafeMutableRawPointer? {
    if let h = slHandle, let s = dlsym(h, name) { return s }
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)   // RTLD_DEFAULT
}

private typealias NewConnFn      = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
private typealias EventPortFn    = @convention(c) (Int32, UnsafeMutablePointer<mach_port_t>) -> Int32
private typealias ConnNotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void
private typealias RegConnFn      = @convention(c) (Int32, ConnNotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32
private typealias ReqWinFn       = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32) -> Int32
private typealias NextEventFn    = @convention(c) (Int32) -> Unmanaged<CGEvent>?

private let fnNewConn    = slSym("SLSNewConnection").map { unsafeBitCast($0, to: NewConnFn.self) }
private let fnEventPort  = slSym("SLSGetEventPort").map { unsafeBitCast($0, to: EventPortFn.self) }
private let fnRegConn    = slSym("SLSRegisterConnectionNotifyProc").map { unsafeBitCast($0, to: RegConnFn.self) }
private let fnReqWindows = slSym("SLSRequestNotificationsForWindows").map { unsafeBitCast($0, to: ReqWinFn.self) }
private let fnNextEvent  = slSym("SLEventCreateNextEvent").map { unsafeBitCast($0, to: NextEventFn.self) }

// @convention(c) callbacks can't capture context, so route through these
// file-scope globals. halo has exactly one subscriber + one connection.
private weak var liveSubscriber: WindowServerEvents?
private var pumpCID: Int32 = 0

private func connectionNotify(_ event: UInt32, _ data: UnsafeMutableRawPointer?,
                              _ len: Int, _ ctx: UnsafeMutableRawPointer?, _ cid: Int32) {
    liveSubscriber?.onEvent?(event)
}

private let drainPump: CFMachPortCallBack = { _, _, _, _ in
    guard let next = fnNextEvent else { return }
    while let ev = next(pumpCID) { ev.release() }   // draining fires the notify procs
}

final class WindowServerEvents {
    static let MOVE:    UInt32 = 806
    static let RESIZE:  UInt32 = 807
    static let REORDER: UInt32 = 808
    static let FRONT:   UInt32 = 1508
    private static let subscribed: [UInt32] = [MOVE, RESIZE, REORDER, FRONT]

    private(set) var cid: Int32 = 0
    /// Fired on the main thread for every subscribed event.
    var onEvent: ((UInt32) -> Void)?

    var available: Bool { fnNewConn != nil && fnEventPort != nil && fnRegConn != nil }

    @discardableResult
    func start() -> Bool {
        guard let newConn = fnNewConn, let regConn = fnRegConn, fnEventPort != nil else {
            Log.line("‼️ SkyLight window-event symbols unavailable — halo cannot run")
            return false
        }
        var c: Int32 = 0
        let err = newConn(0, &c)
        guard err == 0, c != 0 else { Log.line("‼️ SLSNewConnection failed err=\(err)"); return false }
        cid = c
        liveSubscriber = self
        pumpCID = c
        for ev in Self.subscribed { _ = regConn(c, connectionNotify, ev, nil) }
        guard wireEventPort(c) else { return false }
        Log.debug("window-event seam up on dedicated cid=\(c)")
        return true
    }

    /// (Re)issue the per-window MOVE/RESIZE subscription. Full-replace, so
    /// pass the whole current window-id set; call whenever it changes.
    func requestWindows(_ wids: [UInt32]) {
        guard let req = fnReqWindows, !wids.isEmpty else { return }
        var list = wids
        _ = list.withUnsafeMutableBufferPointer { req(cid, $0.baseAddress!, Int32($0.count)) }
    }

    private func wireEventPort(_ c: Int32) -> Bool {
        guard let getPort = fnEventPort else { return false }
        var port = mach_port_t(MACH_PORT_NULL)
        guard getPort(c, &port) == 0 else { Log.line("‼️ SLSGetEventPort failed"); return false }
        var ctx = CFMachPortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        guard let machPort = CFMachPortCreateWithPort(kCFAllocatorDefault, port, drainPump, &ctx, nil),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0) else {
            Log.line("‼️ CFMachPort wiring failed"); return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }
}
