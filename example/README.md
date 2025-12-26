# Source SDK Example

This small Flutter example demonstrates embedding the `Source.instance.present(...)` QR widget and performing a local encrypt/decrypt round-trip using a fixed key.

How to run:

```bash
cd example
flutter pub get
flutter run
```

The example uses a fixed 32-char demo key so the round-trip decrypt test is deterministic. 
