# Mo Language v1.1157.0 Bundle

Fix: const fn recursive interpreter block boundary.

- `moc` — self-hosted Mo compiler (x86_64-linux), 2265345 bytes
- `moc.sig` — ED25519 signature (ssh-keygen -Y, namespace mo-release)
- `mo-lang-1.1157.0-src.tar.gz` / `.zip` — source
- `checksums.txt` + `.sig` — SHA256 of all assets
- `demo/fib-*` — fib demo for 4 platforms + signatures
- `mo-lang-1.1157.0-bundle.zip` — all-in-one archive
- `mo-lang-1.1157.0-bundle.zip.sha256` — bundle SHA256

Verify: `cat <file> | ssh-keygen -Y check-novalidate -n mo-release -s <file>.sig`
Public key: release/SIGNING_KEY.pub in source tree.

Gate: 487/0. 336_constfn_branch=142, 335_constfn_multi=98. Bootstrap OK.
