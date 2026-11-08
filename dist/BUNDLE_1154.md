# Mo v1.1154.0 Bundle

本分支存放 v1.1154.0 发布包的签名打包：
- `mo-lang-1.1154.0-bundle.zip` — 全部产物 + 8 个 SSH 签名 + 公钥 + VERIFY.txt
- `mo-lang-1.1154.0-bundle.zip.sha256` — bundle 的 SHA-256

## 验证

```bash
# 1. 校验 bundle 自身
sha256sum -c mo-lang-1.1154.0-bundle.zip.sha256

# 2. 解包
unzip mo-lang-1.1154.0-bundle.zip

# 3. 校验产物 (cd mo-lang-1.1154.0)
sha256sum -c checksums.txt

# 4. 验签 (8 个产物, 每个输出 Good)
cat FILE | ssh-keygen -Y check-novalidate -n mo-release -s FILE.sig
```

公钥在 `release/SIGNING_KEY.pub`（master 分支）。私钥 `~/.ssh/mo-release-signing-key` 不入库。