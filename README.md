# Flake Update Diff Tool

This is the Nix flake update validator. A tool which is able to evaluate a flake
at two points in history, check that everything evaluates, and provide a diff
of the two. In its target state, it will provide a similar function to
DeterminateSystems' awesome `update-flake-lock` tool, but with `nvd` integration
and other bells and whistles that we've come to like.

## How to Use

Currently, this only supports locally-stored flakes, although we are planning to
add support for `git`-based URLs for usage outside of CI pipelines where the
repository is already downloaded.

``` shell
nix run git+https://nayeonie.com/ahuston-0/flake-update-diff-tool -- <flake path>
```

For use in other nix-based projects, `flpudt` is available as
`packages.${system}.flupdt`. Please see our `examples/` folder for common
use-cases.

## Why the name

`flupdt` comes from Fl(ake) Up(date) D(iff) T(ool). The cli is also available as
`flake-update-diff-tool`, for ease-of-use and those who use screen readers or
similar accessibility tools that may not react well to `flupdt`.
