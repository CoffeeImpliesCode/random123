# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2026 CoffeeImpliesCode contributors.
#
# One derivation for this SDK. Variants live in the entry points
# (flake.nix `packages.<system>.static` / `.shared`, devenv.nix
# `outputs.static` / `outputs.shared`), not in here.
#
# Source-only: `src` is this directory, nothing is fetched, no sibling workspace
# is imported, no host path appears. Nix copies a Git work tree as its tracked
# files, so every file the build or the licence closure needs has to be
# committed before a flake build sees it.
{ lib
, stdenv
, zig
, linkage ? "static" # "static" | "dynamic"; the repository default is static.
, optimize ? "ReleaseSafe"
, target ? null # Zig triple for a cross build; null = stdenv.hostPlatform.
, aesni ? false # Paired with -Dcpu=baseline, so it defaults off.
}:

assert zig.version == "0.16.0";
assert builtins.elem linkage [ "static" "dynamic" ];
assert lib.assertMsg (stdenv.hostPlatform.system == stdenv.buildPlatform.system)
  "random123/package.nix builds for the build platform; no Nix cross build here";

stdenv.mkDerivation {
  pname = "random123";
  version = "1.14.0";

  src = lib.cleanSourceWith {
    name = "random123-1.14.0-source";
    src = ./.;
    filter = path: _type:
      let base = baseNameOf (toString path);
      in !(lib.hasPrefix "result-" base
        || builtins.elem base [
          ".git"
          ".devenv"
          ".devenv.flake.nix"
          ".direnv"
          ".zig-cache"
          "zig-cache"
          "zig-out"
          "zig-pkg"
          "result"
        ]);
  };

  strictDeps = true;

  # The zig setup hook appends `-Dcpu=baseline --release=safe` unless this is
  # set. Both are wanted, but as explicit arguments below.
  dontSetZigDefaultFlags = true;

  nativeBuildInputs = [ zig ];

  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  # Without this the Zig setup hook substitutes its own `zig build test` for the
  # check phase, which is a second, differently-flagged build of the same tree.
  dontUseZigCheck = true;

  # The build graph owns the source list, the C flags, and the installation of
  # the artifact, the headers, random123.pc and the licence records. This phase
  # only selects delivery options and places the caches.
  installPhase = ''
    runHook preInstall

    scratch="''${TMPDIR:?TMPDIR is unset}"
    export HOME="$scratch/home"
    export ZIG_GLOBAL_CACHE_DIR="$scratch/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$scratch/zig-local-cache"
    mkdir -p "$HOME" "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

    zig build install \
      -j"''${NIX_BUILD_CORES:-1}" \
      --prefix "$out" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dlinkage=${linkage} \
      ${lib.optionalString aesni "-Daesni=true"} \
      ${lib.optionalString (target != null) "-Dtarget=${target}"}

    runHook postInstall
  '';

  # tests/kat_vectors is test material, not installed output; the Zig manifest
  # (.paths) carries it for the known-answer test. Not installed here.

  doCheck = false;

  enableParallelBuilding = true;

  meta = {
    description = "Random123 counter-based random number generators, compiled with external linkage";
    longDescription = ''
      Random123 v1.14.0 (Salmon and Moraes, D. E. Shaw Research). Upstream is
      header-only and emits no linkable symbol; this package compiles one C
      translation unit of one-line forwarders and installs upstream's headers
      unchanged beside it. Statistical and Monte Carlo use only; not suitable
      for cryptography or security.
    '';
    homepage = "https://github.com/DEShawResearch/random123";
    # Summary label only. include/Random123/features/pgccfeatures.h carries a
    # second notice (Los Alamos National Security, LLC); see NOTICE.md section 3.
    license = lib.licenses.bsd3;
    platforms = lib.platforms.unix;
  };
}