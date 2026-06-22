# Contributing

## Development

Galt is a macOS 14+ Swift Package app.

First-time setup fetches the vendored engine frameworks (sherpa-onnx, onnxruntime, opus).
`opus` is packaged from Homebrew, so install it before `make vendor`:

```bash
brew install opus   # required by make vendor (builds Vendor/opus.xcframework)
make vendor         # fetch/assemble Vendor/*.xcframework (not committed)
swift build
make run
```

Before opening a pull request, run:

```bash
swift build
bash scripts/package-app.sh
```

## Repository Rules

- Keep generated release artifacts out of git. `dist/`, `.build/`, and `.dmg` files are ignored.
- Do not commit API keys, signing certificates, provisioning profiles, or local environment files.
- Prefer small, focused changes. Keep UI, provider, persistence, and packaging changes separated when possible.
- When adding a new external binary dependency, document its source, version, license, and checksum.

## Code Style

- Use SwiftUI and AppKit patterns already present in the project.
- Prefer async/await APIs over Combine.
- Keep user-facing strings specific and task-oriented, especially for permission and error states.
- Add comments only for non-obvious behavior or safety constraints.

## Testing

The project does not yet define a test target. New logic that can be isolated from AppKit, microphone, accessibility, or network APIs should be structured so it can be covered by future Swift Testing tests.
