---
name: wwdr-g3-intermediate-missing
description: A new Apple Development certificate is not a valid signing identity until the WWDR G3 intermediate is in the keychain
metadata:
  type: reference
---

Seen 2026-09-23. Creating an Apple Development certificate in Xcode 27 beta's Manage Certificates put the certificate and its private key in the login keychain, but `security find-identity -v -p codesigning` reported 0 valid identities. The certificate is issued by "Apple Worldwide Developer Relations Certification Authority, OU=G3", and the only WWDR intermediate present was the original one, which expired in February 2023. Xcode did not install G3.

**Why:** without a valid identity, `make build` cannot sign, and an ad-hoc signature changes on every build, which drops the Accessibility grant.

**How to apply:** download https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer, run `security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer`, then confirm `security find-identity -v -p codesigning` lists the identity. The chain check proves the download is genuine.
