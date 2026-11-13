# aubio 0.4.9

aubio comes in as a git submodule at `lib/aubio`, pinned to its tag 0.4.9 (the same source as the tarball Homebrew
builds, https://sources.buildroot.net/aubio/aubio-0.4.9.tar.bz2, sha256
d48282ae4dab83b3dc94c16cf011bcb63835c1c02b515490e1883049c3d1f3da). `aubio` here is a symlink to `lib/aubio/src`, so
the CAubio target compiles it into vChain: no Homebrew aubio, built for vChain's own deployment target, and only the
sources the tempo tracker, FFT and biquad filter need (the rest is excluded in Package.swift). `config.h`
holds the build defines (Accelerate FFT, no libsndfile). Licence: GPL-3.0-or-later, `lib/aubio/COPYING`.
