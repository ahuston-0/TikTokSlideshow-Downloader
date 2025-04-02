{
  self,
  pkgs,
  checks,
  system,
  uv-shell,
  ...
}:

let

  # construct the shell provided by pre-commit for running hooks
  pre-commit = pkgs.mkShell {
    inherit (checks.pre-commit-check) shellHook;
    buildInputs = checks.pre-commit-check.enabledPackages;
  };

  # constructs a custom shell with commonly used utilities
  rad-dev = pkgs.mkShell {
    packages = with pkgs; [
      deadnix
      pre-commit
      treefmt
      statix
      nixfmt-rfc-style
      ruff
      undetected-chromedriver
      chromium
    ];
  };

  # constructs the application in-place
  tiktok = pkgs.mkShell { inputsFrom = [ self.packages.${system}.collections ]; };

in
{
  default = pkgs.mkShell {
    inputsFrom = [
      pre-commit
      rad-dev
      tiktok
      uv-shell.impure
      # uv-shell.uv2nix
    ];
  };
}
