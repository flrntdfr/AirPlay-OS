The Docker commands above are the goal; today the OS is built and deployed with Nix from the
repo root (see [`docs/architecture.md`](./docs/architecture.md)):

```sh
# test (Mac)
nix shell nixpkgs#ruby_3_4 --command ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
nix build .#ampberry-ui                     # renders every page of the web UI as a check

# deploy a device (builds on the nix-darwin linux-builder, pushes the closure over SSH)
nix run github:numtide/system-manager/release-26.05 -- switch --flake .#ampberry --target-host pi@ampberry.local --sudo
DEVICE=ampberry tools/verify.sh

# migrate a box that still runs HiFiBerry OS NG (interactive)
DEVICE=hifiberry AMPBERRY_HOST=pi@HifiBerry.local tools/apply-live.sh
```
