# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2026 CoffeeImpliesCode contributors.
#
# One source-only derivation shared by flake and devenv outputs.
{ lib
, stdenv
, zig
, linkage ? "static" # "static" | "dynamic"; the repository default is static.
, optimize ? "ReleaseSafe"
, target ? null # Zig triple for a cross build; null = stdenv.hostPlatform.
, aesni ? false # Paired with -Dcpu=baseline, so it defaults off.
}:

assert zig.version == "0.17.0";
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

  # Set Zig flags explicitly in installPhase.
  dontSetZigDefaultFlags = true;

  nativeBuildInputs = [ zig ];

  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  # Disable the Zig setup hook's alternate check phase.
  dontUseZigCheck = true;

  # Select delivery options and caches; build.zig installs the artifacts.
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
    # Additional upstream header notices are recorded in NOTICE.md.
    license = lib.licenses.bsd3;
    platforms = lib.platforms.unix;
  };
}