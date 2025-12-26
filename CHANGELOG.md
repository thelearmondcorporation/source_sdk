# 1.0.0+3

All notable changes to this project will be documented in this file.

### Added
- Initial Source SDK implementation that generates AES-256-CBC encrypted QR payloads.
- `Source.instance.present(...)` embeddable Widget to render encrypted QR codes.
- Automatic secure generation and platform secure storage of a 32-byte encryption key (`source_encryption_key`).
- Payload includes `transaction` and `merchant` objects. Merchant uses Source `accountId`.
- Helpers to decode payloads (`decodePayload`, `decodePayloadWithMerchant`) and `payWithApi` helper.
- `README.md` and `INSTRUCTIONS.md` documentation files.

### Security
- Uses AES-256-CBC with IV prepended to ciphertext; base64url encoded for QR transport.

### Notes
- This SDK provides encrypted QR generation only; payment UX/paysheet
	implementations are intentionally left to integrators.
