# dev-aws

Tools and scripts for AWS development.

## Development

### Prerequisites

- [pre-commit](https://pre-commit.com/)
- [shellcheck](https://www.shellcheck.net/)
- [bats-core](https://github.com/bats-core/bats-core)

**macOS:**

```bash
pip install pre-commit
brew install shellcheck bats-core
```

**Linux (Debian/Ubuntu):**

```bash
pip install pre-commit
apt-get install shellcheck bats
```

### Setup

```bash
pre-commit install
./tests/setup-bats.sh
```

### Linting

```bash
pre-commit
pre-commit run --all-files
```

### Testing

```bash
bats tests
```
