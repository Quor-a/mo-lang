# Mo Language v1.1159.0 Bundle

const fn break / continue.

- `moc` — self-hosted Mo compiler (x86_64-linux)
- `mo-lang-1.1159.0-src.tar.gz` / `.zip` — full source at tag v1.1159.0
- `demo/fib-*` — cross-compiled demos (aarch64-linux, aarch64-macos, x86_64-linux, x86_64-windows)
- `checksums.txt` / `.sig` — sha256 manifest, ED25519 signed
- bundle sha256: see `mo-lang-1.1159.0-bundle.zip.sha256`

Verify: `cat ./-file | ssh-keygen -Y check-novalidate -n mo-release -s ./-file.sig`
