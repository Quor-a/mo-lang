# Mo Language v1.1158.0 Bundle

const fn loops, locals and assignment.

- `moc` — self-hosted Mo compiler (x86_64-linux)
- `moc.sig` — ED25519 signature (namespace mo-release)
- `mo-lang-1.1158.0-src.tar.gz` / `.zip` — source
- `checksums.txt` + `.sig` — SHA256 of all assets
- `demo/fib-*` — fib demo for 4 platforms + signatures
- `demo/constfn.mo` — const fn loop examples
- `mo-lang-1.1158.0-bundle.zip` + `.sha256`

Verify: `cat <file> | ssh-keygen -Y check-novalidate -n mo-release -s <file>.sig`
Gate: 488/0. 337=136, 336=142, 335=98. Bootstrap OK.
