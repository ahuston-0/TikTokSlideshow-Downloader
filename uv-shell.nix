{
  lib,
  pkgs,
  python,
  workspace,
  pythonSet,
  ...
}:

{
  # It is of course perfectly OK to keep using an impure virtualenv workflow and only use uv2nix to build packages.
  # This devShell simply adds Python and undoes the dependency leakage done by Nixpkgs Python infrastructure.
  impure = pkgs.mkShell {
    packages = [
      python
      pkgs.uv
    ];
    env =
      {
        # Prevent uv from managing Python downloads
        UV_PYTHON_DOWNLOADS = "never";
        # Force uv to use nixpkgs Python interpreter
        UV_PYTHON = python.interpreter;
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        # Python libraries often load native shared objects using dlopen(3).
        # Setting LD_LIBRARY_PATH makes the dynamic library loader aware of libraries without using RPATH for lookup.
        LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
      };
    shellHook = ''
      unset PYTHONPATH
    '';
  };

  # This devShell uses uv2nix to construct a virtual environment purely from Nix, using the same dependency specification as the application.
  # The notable difference is that we also apply another overlay here enabling editable mode ( https://setuptools.pypa.io/en/latest/userguide/development_mode.html ).
  #
  # This means that any changes done to your local files do not require a rebuild.
  #
  # Note: Editable package support is still unstable and subject to change.
  uv2nix =
    let
      # Create an overlay enabling editable mode for all local dependencies.
      editableOverlay = workspace.mkEditablePyprojectOverlay {
        # Use environment variable
        root = "$REPO_ROOT";
        # Optional: Only enable editable for these packages
        # members = [ "flupdt" ];
      };

      # Override previous set with our overrideable overlay.
      editablePythonSet = pythonSet.overrideScope (
        lib.composeManyExtensions [
          editableOverlay

          # Apply fixups for building an editable package of your workspace packages
          (final: prev: {
            flupdt = prev.flupdt.overrideAttrs (old: {
              # It's a good idea to filter the sources going into an editable build
              # so the editable package doesn't have to be rebuilt on every change.
              src = lib.fileset.toSource {
                root = old.src;
                fileset = lib.fileset.unions [
                  (old.src + "/pyproject.toml")
                  (old.src + "/README.md")
                  (old.src + "/flupdt/__init__.py")
                  (old.src + "/flupdt/cli.py")
                  (old.src + "/flupdt/common.py")
                  (old.src + "/flupdt/flake_build.py")
                  (old.src + "/flupdt/flake_diff.py")
                  (old.src + "/flupdt/flake_eval.py")
                  (old.src + "/flupdt/flake_show.py")
                  (old.src + "/flupdt/main.py")
                ];
              };

              # Hatchling (our build system) has a dependency on the `editables` package when building editables.
              #
              # In normal Python flows this dependency is dynamically handled, and doesn't need to be explicitly declared.
              # This behaviour is documented in PEP-660.
              #
              # With Nix the dependency needs to be explicitly declared.
              nativeBuildInputs =
                old.nativeBuildInputs
                ++ final.resolveBuildSystem {
                  editables = [ ];
                };
            });

          })
        ]
      );

      # Build virtual environment, with local packages being editable.
      #
      # Enable all optional dependencies for development.
      virtualenv = editablePythonSet.mkVirtualEnv "flupdt-dev-env" workspace.deps.all;

    in
    pkgs.mkShell {
      packages = [
        virtualenv
        pkgs.uv
      ];

      env = {
        # Don't create venv using uv
        UV_NO_SYNC = "1";

        # Force uv to use Python interpreter from venv
        UV_PYTHON = "${virtualenv}/bin/python";

        # Prevent uv from downloading managed Python's
        UV_PYTHON_DOWNLOADS = "never";
      };

      shellHook = ''
        # Undo dependency propagation by nixpkgs.
        unset PYTHONPATH

        # Get repository root using git. This is expanded at runtime by the editable `.pth` machinery.
        export REPO_ROOT=$(git rev-parse --show-toplevel)
      '';
    };
}
