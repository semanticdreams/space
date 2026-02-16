# Quick Start

Run these commands from the repository root:

```bash
make build
make run
```

Run tests with the standard environment:

```bash
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH=$(pwd)/assets \
make test
```
