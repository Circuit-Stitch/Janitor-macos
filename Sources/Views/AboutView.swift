//  AboutView.swift
//  The About window: who made Janitor, which build this is, and what it is licensed
//  under.
//
//  It replaces the standard AppKit panel rather than decorating it. The stock panel
//  draws the app icon and the version and has no room for a publisher mark, a license
//  statement, and a way through to the third-party notices. All three belong here.
//
//  Every string below comes from the bundle. The version, the build, and the copyright
//  are read from Info.plist, which is generated from project.yml, so this window cannot
//  disagree with what was shipped. Nothing is hardcoded that the build already knows.
//
//  The logo is one asset. `circuit-stitch.svg` is a single-color stroke drawing, so the
//  asset catalog renders it as a template and the tint comes from `BrandStroke` — amber
//  in light appearance, gold in dark. That keeps the brand color while still following
//  the operator's appearance and contrast settings, which a pair of fixed-color images
//  would not.

import SwiftUI

struct AboutView: View {
    /// The scene id. Opening the window and declaring it both name it, so they name one
    /// constant.
    static let windowID = "about"

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            // The catalog already sets the template intent. Naming it here too means the
            // tint survives someone editing Contents.json without reading this file.
            Image("CircuitStitch")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(Color("BrandStroke"))
                .accessibilityLabel("Circuit Stitch")

            VStack(spacing: 4) {
                Text("Janitor")
                    .font(.title2.weight(.semibold))
                Text(Self.versionLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("An ephemeral desktop client onto your AWS secrets. It stores no "
                + "secrets and no credentials of its own.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 6) {
                Text(Self.copyright)
                    .font(.footnote)
                Text("Free software under the Apache License 2.0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Link("circuitstitch.com", destination: Self.site)
                Text("·").foregroundStyle(.tertiary)
                Link("Source", destination: Self.source)
                Text("·").foregroundStyle(.tertiary)
                Button("Acknowledgments…") {
                    openWindow(id: AcknowledgmentsView.windowID)
                }
                .buttonStyle(.link)
            }
            .font(.footnote)
        }
        .padding(24)
        .frame(width: 340)
    }

    // MARK: What the bundle knows

    /// `Version 0.1.0 (1)`, from the two keys Info.plist carries.
    ///
    /// A missing key means the plist was not generated, which is a build problem rather
    /// than something to paper over at runtime. It shows as a blank rather than a crash,
    /// because an About window is not worth trapping on.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    /// The copyright line, which lives in Info.plist so the About window and the Finder
    /// inspector cannot drift apart.
    static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    // The first URLs the Swift shell opens. The sign-in browser hand-off happens in the
    // Rust core, not here. Neither needs a fourth entitlement: handing a URL to
    // LaunchServices is allowed from inside the sandbox.
    static let site = URL(string: "https://www.circuitstitch.com")!
    static let source = URL(string: "https://github.com/Circuit-Stitch/Janitor-macos")!
}
