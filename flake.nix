{
  description = "Application packaged using poetry2nix";

  nixConfig = {
    substituters = [
      "https://cache.nixos.org/?priority=1&want-mass-query=true"
      "https://attic.nayeonie.com/nix-cache"
      "https://nix-community.cachix.org/?priority=10&want-mass-query=true"
    ];
    trusted-substituters = [
      "https://cache.nixos.org"
      "https://attic.nayeonie.com/nix-cache"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-cache:trR+y5nwpQHR4hystoogubFmp97cewkjWeqqbygRQRs="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        # nixpkgs-stable.follows = "nixpkgs-stable";
        # flake-compat.follows = "flake-compat";
      };
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
      };
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        inherit (nixpkgs) lib;

        # Load a uv workspace from a workspace root.
        # Uv2nix treats all uv projects as workspace projects.
        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

        # Create package overlay from workspace.
        overlay = workspace.mkPyprojectOverlay {
          # Prefer prebuilt binary wheels as a package source.
          # Sdists are less likely to "just work" because of the metadata missing from uv.lock.
          # Binary wheels are more likely to, but may still require overrides for library dependencies.
          sourcePreference = "wheel";
          #sourcePreference = "sdist";
          # Optionally customise PEP 508 environment
          # environ = {
          #   platform_release = "5.10.65";
          # };
        };

        # Extend generated overlay with build fixups
        #
        # Uv2nix can only work with what it has, and uv.lock is missing essential metadata to perform some builds.
        # This is an additional overlay implementing build fixups.
        # See:
        # - https://pyproject-nix.github.io/uv2nix/FAQ.html
        pyprojectOverrides =
          final: prev:
          # Implement build fixups here.
          # Note that uv2nix is _not_ using Nixpkgs buildPythonPackage.
          # It's using https://pyproject-nix.github.io/pyproject.nix/build.html
          let
            inherit (final) resolveBuildSystem;
            inherit (builtins) mapAttrs;

            # Build system dependencies specified in the shape expected by resolveBuildSystem
            # The empty lists below are lists of optional dependencies.
            #
            # A package `foo` with specification written as:
            # `setuptools-scm[toml]` in pyproject.toml would be written as
            # `foo.setuptools-scm = [ "toml" ]` in Nix
            buildSystemOverrides = {
              attrs = {
                hatchling = [ ];
                hatch-vcs = [ ];
                hatch-fancy-pypi-readme = [ ];
              };
              hatchling = {
                pathspec = [ ];
                pluggy = [ ];
                packaging = [ ];
                trove-classifiers = [ ];
              };
              pathspec = {
                flit-core = [ ];
              };
              pluggy = {
                setuptools = [ ];
              };
              trove-classifiers = {
                setuptools = [ ];
              };
              tomli.flit-core = [ ];
              coverage.setuptools = [ ];
              blinker.setuptools = [ ];
              certifi.setuptools = [ ];
              charset-normalizer.setuptools = [ ];
              idna.flit-core = [ ];
              urllib3 = {
                hatchling = [ ];
                hatch-vcs = [ ];
              };
              pip = {
                setuptools = [ ];
                wheel = [ ];
              };
              packaging.flit-core = [ ];
              requests.setuptools = [ ];
              pysocks.setuptools = [ ];
              pytest-cov.setuptools = [ ];
              tqdm.setuptools = [ ];
              tikapi.setuptools = [ ];
              undetected-chromedriver.setuptools = [ ];
            };

          in
          mapAttrs (
            name: spec:
            prev.${name}.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ resolveBuildSystem spec;
            })
          ) buildSystemOverrides;

        # This example is only using x86_64-linux
        pkgs = nixpkgs.legacyPackages.${system};

        # Use Python 3.12 from nixpkgs
        python = pkgs.python312;

        # Construct package set
        pythonSet =
          # Use base package set from pyproject.nix builders
          (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (
              lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                overlay
                pyprojectOverrides
              ]
            );

        uv-shell = import ./uv-shell.nix {
          inherit
            lib
            pkgs
            python
            workspace
            pythonSet
            ;
        };
      in
      rec {
        # Package a virtual environment as our main application.
        #
        # Enable no optional dependencies for production build.
        packages = rec {
          collections = pythonSet.mkVirtualEnv "collections-env" workspace.deps.default;
          following = pythonSet.mkVirtualEnv "collections-env" workspace.deps.default;
          default = collections;
        };

        # Make hello runnable with `nix run`
        apps = rec {
          default = collections;
          collections = {
            type = "app";
            program = "${packages.collections}/bin/collections";
          };
          following = {
            type = "app";
            program = "${packages.following}/bin/following";
          };
        };

        formatter = pkgs.nixfmt-rfc-style;

        devShells = import ./shell.nix {
          inherit
            self
            pkgs
            inputs
            system
            checks
            uv-shell
            ;
        };
        checks = import ./checks.nix { inherit inputs system formatter; };
      }
    );
  # // {
  #   hydraJobs = import ./hydra/jobs.nix { inherit (self) inputs outputs; };
  # };
}
