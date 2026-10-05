# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2026 CoffeeImpliesCode contributors.
#
# Canonical development environment. Tools only: entering the shell must not
# build the SDK. The packaging route is `devenv build outputs.static` and
# `devenv build outputs.shared`, which call the same ./package.nix the flake
# uses.
{ pkgs, lib, ... }:

let
  zig = pkgs.zig_0_16;
  staticPkg = pkgs.callPackage ./package.nix { inherit zig; linkage = "static"; };
  sharedPkg = pkgs.callPackage ./package.nix { inherit zig; linkage = "dynamic"; };

  # The directory this module was evaluated against. `./.` is a path literal
  # relative to the file that names it, so it is this checkout -- never the
  # directory the caller happened to run `devenv shell` from. That distinction
  # is the whole fix: devenv materialises tasks and scripts as generated shell
  # programs that inherit the caller's working directory, and `--from
  # path:<sdk>` entered from a scratch project directory leaves every body
  # below standing in a directory with no `build.zig` and no
  # `UPSTREAM.sha256`.
  #
  # `builtins.toString` converts the path instead of interpolating it into a
  # string literal, so the result stays this working tree rather than a copy
  # of the whole SDK in the read-only store: the store copy is not the tree
  # `sha256sum -c` describes. No host path is written in this file -- the
  # value is read out of the module's own location when it is evaluated, so it
  # tracks wherever this checkout is.
  #
  # `lib.escapeShellArg` makes the value one shell word, because a checkout
  # path is not guaranteed to be free of spaces or quotes; every body below
  # therefore interpolates it unquoted, as `cd ${sdkRoot}`.
  sdkRoot = lib.escapeShellArg (builtins.toString ./.);

  # One prefix policy, shared by the two bodies that write a delivery tree.
  # This is a shell function rather than a Nix string so each caller embeds it
  # verbatim: there is one copy of the precedence, not two that can drift.
  #
  # It prints the prefix and returns 0, or explains on stderr and returns 1;
  # a caller captures it with `|| exit 1` so a refusal cannot be read as an
  # empty prefix. Nothing here chooses a location for the caller: the first
  # branch is an argument the caller passed, the rest are directories the
  # caller exported. `build` passes no argument -- a caller-supplied install
  # prefix is this SDK's `install` API and stays there.
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

  # The cache directory every build entry passes explicitly. `zig build` with
  # no `--cache-dir` uses `$ZIG_LOCAL_CACHE_DIR` itself, which `preamble` has
  # already placed outside the checkout, so this names this SDK's own
  # subdirectory inside it: the `$CACHE/<repo>/<target>` shape AGENTS.md:158
  # asks for, and a cache manifest this graph locks alone. The name is spelled
  # once here and expanded by the shell from the caller's own variable, whose
  # value `preamble` fills when it is missing.
  # This is a double-quoted string, so the indented string's `''$` escape does
  # not apply here: `${` is Nix interpolation of a Nix variable, and
  # `ZIG_LOCAL_CACHE_DIR` is not one -- evaluation stops on it before any task
  # can run. Spelled without braces the value is literal text, copied out
  # unchanged for the shell to expand.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/random123";

  # What every body below runs before it reaches the compiler: the
  # self-located directory, then the two cache variables, then the directory
  # `--cache-dir` names. It lives in the body rather than in `enterShell`
  # because `zig build` has to be told where its cache is on every invocation,
  # and `devenv tasks run --mode single` bypasses the shell hooks, so a default
  # filled only on entry would not be in the environment of a canonical
  # command.
  #
  # A cache the caller already exported is used exactly as it stands and is
  # never rewritten. One that is missing is filled from `XDG_CACHE_HOME`, then
  # from `TMPDIR`; with neither exported the body prints what it needs and
  # exits non-zero before a compiler runs, rather than choose a location or
  # fall back to `.zig-cache`.
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

  # Lazy: nothing is realised until `devenv build outputs.<name>`.
  outputs.static = staticPkg;
  outputs.shared = sharedPkg;
  outputs.default = staticPkg;

  # Every exec body begins with `preamble`: it changes to `sdkRoot` and fills
  # the cache variables, for the reasons the binding records. A per-entry `cwd`
  # option would not reach the generated shell program, and `$DEVENV_ROOT` is
  # the scratch project -- exactly what these bodies must not build in.
  #
  # Two of the nine write a delivery tree and so carry `--prefix` resolved by
  # `externalPrefix`: `build`, because Zig's default step *is* the install
  # step, and `install`. The other seven -- `test`, `test-release-safe`,
  # `smoke`, `check`, `matrix`, `consumer`, `provenance` -- depend on compile
  # and run steps only: `build.zig:1014` and `consumer/build.zig:77` each take
  # just `&run.step`, so a `--prefix` there would be a flag that changes
  # nothing.
  #
  # All eight builds pass `-j8`, `--cache-dir "${cacheDir}"` and
  # `--summary all`: the same three flags in the same order in every entry,
  # with `-j8` ahead of the arguments `install` forwards, so a caller's tail
  # still has the last word. No entry leaves the cache to `zig build` to pick.
  scripts = {
    # Zig's default step *is* the install step -- `b.installArtifact` at
    # `build.zig:266` puts the bridge, the headers, `random123.pc` and the
    # licence records there -- so a bare `zig build` writes `zig-out/` into
    # this checkout unless it is given a prefix. This is the same hole the
    # `install` script had, reached by a shorter name.
    build.exec = ''
      ${preamble}
      ${externalPrefix}
      prefix="$(random123_external_prefix)" || exit 1
      mkdir -p "$prefix"
      zig build -j8 --cache-dir "${cacheDir}" --summary all --prefix "$prefix"
    '';

    # Delivery output goes outside the checkout. A prefix passed as the first
    # argument always wins, as before; otherwise `externalPrefix` picks it, and
    # with nothing to pick from the script refuses rather than choose. Remaining
    # caller arguments are forwarded to `zig build install` untouched.
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
      # Compile-only: every public facade method and the example; nothing runs.
      ${preamble}
      zig build check -j8 --cache-dir "${cacheDir}" --summary all
    '';

    matrix.exec = ''
      # Six targets in one invocation. riscv64-linux-gnu and wasm32-wasi fail
      # inside upstream's architecture guard; that is the recorded limit.
      ${preamble}
      zig build matrix -j8 --cache-dir "${cacheDir}" --summary all
    '';

    # The dependent package in `consumer/`, driven as this package's own step.
    consumer.exec = ''
      ${preamble}
      zig build consumer -j8 --cache-dir "${cacheDir}" --summary all
    '';

    # Compares the bytes this fork did not author against the digests recorded
    # when the tree was acquired, in the tree those digests describe.
    provenance.exec = ''
      ${preamble}
      sha256sum -c UPSTREAM.sha256
    '';
  };
}