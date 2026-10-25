# wisprM

Native desktop and mobile dictation apps, maintained in one Git repository.

## Repository layout

| Directory | Contents |
| --- | --- |
| [desktop/](desktop/README.md) | macOS SwiftUI/AppKit app, Swift package, Python/MLX runtime, resources, scripts and tests |
| [wisprM-iOS/](wisprM-iOS/README.md) | iPhone SwiftUI app, keyboard extension, Xcode project, native inference packages, scripts and tests |
| [docs/](docs/plans/) | Repository-wide design notes |

The desktop Swift package also exports the shared **WisprCore** library used by both apps. Its source remains in [desktop/Sources/WisprCore](desktop/Sources/WisprCore); the mobile packages and Xcode project reference that package directly. There is one shared implementation.

## Quick commands

Run these from the repository root:

~~~sh
make desktop       # Build desktop/dist/wisprM.app
make mobile        # Build the iOS Simulator app
make test          # Run both apps Swift and Python tests
make desktop-test  # Desktop and shared-core tests
make mobile-test   # Mobile tests
~~~

Desktop build, install, runtime setup, open and verification commands still work from the root:

~~~sh
make install
make setup-runtime
make open
make verify
~~~

For app-specific commands, work directly in the app directory or use Make's -C option:

~~~sh
make -C desktop help
make -C wisprM-iOS build
make mobile-project
make mobile-device
~~~

See the [desktop guide](desktop/README.md) and [mobile guide](wisprM-iOS/README.md) for prerequisites, model setup, signing and platform-specific behavior. Desktop runtime setup requires Python 3.12 or 3.13. Mobile signing stays in the ignored local signing configuration; do not commit personal signing overrides.
