// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

// vChain: SwiftUI front end (Sources/VChain) over the C++ engine (Sources/VChainEngine).
// Build the app with ./build.sh; prerequisites: the lib/link and lib/aubio submodules.
let package = Package(
    name: "VChain",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "VChain", targets: ["VChain"])],
    // Sparkle: app updates (build.sh copies Sparkle.framework into Contents/Frameworks).
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        // aubio 0.4.9 from the lib/aubio submodule (Sources/CAubio/README.md): compiled in, FFT through Accelerate.
        // Only what the tempo tracker (onset, peak picking, spectral descriptors, phase vocoder), the FFT and the biquad
        // filter need; io, pitch, notes, synth, DCT/MFCC/filterbanks, weighting and resampling stay out.
        .target(
            name: "CAubio",
            exclude: [
                "README.md", "aubio/wscript_build", "aubio/io", "aubio/pitch", "aubio/notes", "aubio/synth",
                "aubio/spectral/dct.c", "aubio/spectral/dct_accelerate.c", "aubio/spectral/dct_fftw.c",
                "aubio/spectral/dct_ipp.c", "aubio/spectral/dct_ooura.c", "aubio/spectral/dct_plain.c",
                "aubio/spectral/filterbank.c", "aubio/spectral/filterbank_mel.c", "aubio/spectral/mfcc.c",
                "aubio/spectral/ooura_fft8g.c", "aubio/spectral/tss.c",
                "aubio/temporal/a_weighting.c", "aubio/temporal/c_weighting.c", "aubio/temporal/resampler.c",
                "aubio/utils/parameter.c", "aubio/utils/windll.c", "aubio/fmat.c",
            ],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("aubio"),
                .define("HAVE_CONFIG_H"),
                .unsafeFlags(["-w"]), // third-party code: its warnings aren't ours to fix
            ],
            linkerSettings: [.linkedFramework("Accelerate")]
        ),
        // Beat/tempo/downbeat analysis and the Link-driving logic: pure C++ (aubio only), no Core Audio, no real
        // Link, no clock reads. Shared by the engine and VChainBench, so the bench tests the app's code.
        .target(
            name: "VChainDSP",
            dependencies: ["CAubio"],
            cxxSettings: [.unsafeFlags(["-Wno-deprecated-declarations"])]
        ),
        // Beat This! through Core ML (Objective-C++ inside, plain C++ interface); used by the engine and the bench.
        .target(
            name: "VChainNN",
            dependencies: ["VChainDSP"],
            cxxSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("CoreML"), .linkedFramework("Foundation")]
        ),
        // C++ / Objective-C++ engine; Swift sees only include/vchain_engine.h (plain C).
        .target(
            name: "VChainEngine",
            dependencies: ["CAubio", "VChainDSP", "VChainNN"],
            cxxSettings: [
                .headerSearchPath("../../lib/link/include"),
                .headerSearchPath("../../lib/link/modules/asio-standalone/asio/include"),
                .define("LINK_PLATFORM_MACOSX", to: "1"),
                // system_audio.mm uses manual retain/release.
                .unsafeFlags(["-fno-objc-arc", "-Wno-deprecated-declarations"]),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"), .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreFoundation"), .linkedFramework("CoreMIDI"),
                .linkedFramework("ScreenCaptureKit"), .linkedFramework("CoreMedia"),
                .linkedFramework("CoreGraphics"), .linkedFramework("Foundation"),
            ]
        ),
        // Pure logic for the keychain UI (Foundation/CoreGraphics only); checked by VChainChecks.
        .target(name: "VChainKit"),
        // Offline bench: runs VChainDSP over synthetic or annotated audio against a simulated Link (never the
        // network). Link headers only for the self-test against a real, never-enabled ableton::Link.
        .executableTarget(
            name: "VChainBench",
            dependencies: ["VChainDSP", "VChainNN"],
            cxxSettings: [
                .headerSearchPath("../VChainEngine"), // real_link_port.h only (checked against the app's Link path)
                .headerSearchPath("../../lib/link/include"),
                .headerSearchPath("../../lib/link/modules/asio-standalone/asio/include"),
                .define("LINK_PLATFORM_MACOSX", to: "1"),
                .unsafeFlags(["-Wno-deprecated-declarations"]),
            ],
            linkerSettings: [.linkedFramework("AudioToolbox"), .linkedFramework("CoreFoundation")]
        ),
        // XCTest is unavailable with Command Line Tools only: scripts/check.sh runs this instead.
        .executableTarget(name: "VChainChecks", dependencies: ["VChainKit", "VChainEngine"]),
        .executableTarget(
            name: "VChain",
            dependencies: ["VChainEngine", "VChainKit", .product(name: "Sparkle", package: "Sparkle")],
            // build.sh copies Fonts/ into Contents/Resources (ATSApplicationFontsPath).
            exclude: ["Fonts"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
