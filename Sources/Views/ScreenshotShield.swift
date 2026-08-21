//  ScreenshotShield.swift
//  Keeps the window out of other processes' screen captures while a Value is revealed.
//
//  `NSWindow.sharingType` is what decides whether another process can read a window's
//  pixels. Set to `.none` the window is excluded from screenshots, screen recordings,
//  and the app-switcher and Mission Control thumbnails that other software renders. It
//  is the same control password managers use.
//
//  It is applied only while a cell is revealed, because the masked matrix is safe to
//  capture and a permanently unshareable window would break screen sharing during
//  ordinary work.
//
//  This defends against capture by other software. It does not defend against a camera
//  pointed at the screen, and the operator watching is the entire point of a reveal.

import SwiftUI

/// Sets the host window's sharing type from `redacted`.
struct ScreenshotShield: NSViewRepresentable {
    let redacted: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The window is nil until the view joins the hierarchy, so read it each update
        // rather than caching it at creation.
        DispatchQueue.main.async {
            view.window?.sharingType = redacted ? .none : .readOnly
        }
    }
}

extension View {
    /// Exclude this view's window from other processes' screen captures while
    /// `redacted` holds.
    func screenshotRedacted(_ redacted: Bool) -> some View {
        background(ScreenshotShield(redacted: redacted))
    }
}
