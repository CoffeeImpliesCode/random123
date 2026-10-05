# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2026 CoffeeImpliesCode contributors.
#
# Two packages from one derivation: `packages.<system>.static` and `.shared`.
# `default` passes no linkage, so it is the repository's own static default.
# Development is `devenv` (devenv.nix); there is no devShell here, so the
# toolchain version is decided in one place.
{
  description = "Random123 counter-based random number generators, compiled for Zig, C and C++";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = fn: nixpkgs.lib.genAttrs systems (system: fn nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        static = pkgs.callPackage ./package.nix {
          zig = pkgs.zig_0_16;
          linkage = "static";
        };
        shared = pkgs.callPackage ./package.nix {
          zig = pkgs.zig_0_16;
          linkage = "dynamic";
        };
        default = static;
      });

      # Another optimize mode, without adding an attribute for each:
      #   nix build --impure --expr '
      #     let f = builtins.getFlake (toString ./.);
      #         p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
      #     in p.callPackage ./package.nix { zig = p.zig_0_16; optimize = "Debug"; }'
    };
}