# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2026 CoffeeImpliesCode contributors.
#
# Development shell and tasks; SDK outputs build on demand.
{ pkgs, lib, ... }:

let
  zig = pkgs.zig_0_16;
  staticPkg = pkgs.callPackage ./package.nix { inherit zig; linkage = "static"; };
  sharedPkg = pkgs.callPackage ./package.nix { inherit zig; linkage = "dynamic"; };

  # Resolve this checkout from the file, not the caller's cwd or a store copy.
  # Escape it as one shell word because checkout paths may contain spaces.
  sdkRoot = lib.escapeShellArg (builtins.toString ./.);

  # Resolve the prefix from an argument, cache root, XDG cache or TMPDIR.
  # Refuse when none is set; never install into the checkout by default.
  externalPrefix = ''
    random123_external_prefix() {
      if [ -n "''${1:-}" ]; then
        printf '%s\n' "$1"
      elif [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
        printf '%s\n' "$ZIG_LOCAL_CACHE_DIR/random123-install"
      elif [ -n "''${XDG_CACHE_HOME:-}" ]; then
        printf '%s\n' "$XDG_CACHE_HOME/random123/install"
      elif [ -n "''${TMPDIR:-}" ]; then
        printf '%s\n' "$TMPDIR/random123-install"
      else
        echo "random123: this script installs into a prefix, never into the" >&2
        echo "checkout. Name one as the install script's first argument, or" >&2
        echo "export ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME or TMPDIR." >&2
        return 1
      fi
    }
  '';

  # Keep the Zig local cache under the caller's cache root.
  # Use `$VAR`; `${VAR}` would be Nix interpolation here.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/random123";

  # Each task sets its root and caches; `tasks run` bypasses shell hooks.
  # Preserve caller values, fill from XDG_CACHE_HOME or TMPDIR, and fail if neither exists.
  preamble = ''
    cd ${sdkRoot} || exit 1
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        : "''${ZIG_LOCAL_CACHE_DIR:=$XDG_CACHE_HOME/random123/zig-local-cache}"
        : "''${ZIG_GLOBAL_CACHE_DIR:=$XDG_CACHE_HOME/zig-global-cache}"
      elif [ -n "''${TMPDIR:-}" ]; then
        : "''${ZIG_LOCAL_CACHE_DIR:=$TMPDIR/random123/zig-local-cache}"
        : "''${ZIG_GLOBAL_CACHE_DIR:=$TMPDIR/zig-global-cache}"
      else
        echo "random123: a Zig cache directory is unset and neither" >&2
        echo "XDG_CACHE_HOME nor TMPDIR is set, so none is chosen here." >&2
        echo "Export ZIG_LOCAL_CACHE_DIR and ZIG_GLOBAL_CACHE_DIR, or one" >&2
        echo "of XDG_CACHE_HOME and TMPDIR, before entering the shell." >&2
        exit 1
      fi
    fi
    export ZIG_LOCAL_CACHE_DIR ZIG_GLOBAL_CACHE_DIR
    mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"
  '';
in
{
  packages = with pkgs; [
    zig
    bash
    pkg-config
    git
  ];

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "random123 needs Zig 0.16.0; devenv.yaml pins the nixpkgs providing pkgs.zig_0_16.";
    }
  ];

  outputs.static = staticPkg;
  outputs.shared = sharedPkg;
  outputs.default = staticPkg;

  # Tasks use the checkout root and explicit cache paths, even when shell hooks are bypassed.
  # Only build and install resolve an external prefix for delivery output.
  scripts = {
    # The default Zig step installs; keep its output outside the checkout.
    build.exec = ''
      ${preamble}
      ${externalPrefix}
      prefix="$(random123_external_prefix)" || exit 1
      mkdir -p "$prefix"
      zig build -j8 --cache-dir "${cacheDir}" --summary all --prefix "$prefix"
    '';

    # Use an explicit prefix or require an external cache/temp prefix.
    install.exec = ''
      ${preamble}
      ${externalPrefix}
      prefix="$(random123_external_prefix "''${1:-}")" || exit 1
      mkdir -p "$prefix"
      zig build install -j8 --cache-dir "${cacheDir}" --summary all --prefix "$prefix" "''${@:2}"
      printf '%s\n' "installed to $prefix"
    '';

    test.exec = ''
      ${preamble}
      zig build test -j8 --cache-dir "${cacheDir}" --summary all
    '';

    test-release-safe.exec = ''
      ${preamble}
      zig build test -j8 --cache-dir "${cacheDir}" --summary all -Doptimize=ReleaseSafe
    '';

    smoke.exec = ''
      ${preamble}
      zig build smoke -j8 --cache-dir "${cacheDir}" --summary all
    '';

    check.exec = ''
      ${preamble}
      zig build check -j8 --cache-dir "${cacheDir}" --summary all
    '';

    matrix.exec = ''
      ${preamble}
      zig build matrix -j8 --cache-dir "${cacheDir}" --summary all
    '';

    consumer.exec = ''
      ${preamble}
      zig build consumer -j8 --cache-dir "${cacheDir}" --summary all
    '';

    provenance.exec = ''
      ${preamble}
      sha256sum -c UPSTREAM.sha256
    '';
  };
}