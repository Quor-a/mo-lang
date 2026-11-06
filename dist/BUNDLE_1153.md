# Mo v1.1153.0 Bundle

本分支存放 v1.1153.0 发布包的签名打包：
- `mo-lang-1.1153.0-bundle.zip` — 全部产物 + 8 个 SSH 签名 + 公钥 + VERIFY.txt
- `mo-lang-1.1153.0-bundle.zip.sha256` — bundle 的 SHA256

校验（消息从 stdin 读）：
```bash
sha256sum -c mo-lang-1.1153.0-bundle.zip.sha256
cat checksums.txt | ssh-keygen -Y check-novalidate -n mo-release -s checksums.txt.sig
```

GitHub Release: https://github.com/Quor-a/mo-lang/releases/tag/v1.1153.0
