# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2026 CoffeeImpliesCode contributors.
#
# Static is the default; devenv.nix owns the development shell.
{
  description = "Random123 counter-based random number generators, compiled for Zig, C and C++";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

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
          zig = pkgs.zig_0_17;
          linkage = "static";
        };
        shared = pkgs.callPackage ./package.nix {
          zig = pkgs.zig_0_17;
          linkage = "dynamic";
        };
        default = static;
      });

    };
}