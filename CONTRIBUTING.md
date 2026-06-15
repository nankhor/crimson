# Contributing

First off, thanks for taking the time to contribute!

## Code of Conduct

This project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold its terms.

## How to Contribute

### Report Bugs

Open an issue at <https://github.com/cmoiadib/crimson/issues> with:
- A clear title and description
- Steps to reproduce
- Expected vs actual behavior
- Your environment (Ruby version, OS, terminal)

### Suggest Features

Open an issue with the `enhancement` label describing the feature and its use case.

### Submit Code

1. Fork the repo
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Make your changes
4. Run tests: `bundle exec rake`
5. Commit using conventional commits (e.g., `feat: add support for ...`)
6. Push and open a Pull Request

### Development Setup

```bash
git clone https://github.com/cmoiadib/crimson.git
cd crimson
bundle install
ruby exe/crimson setup
```

### Run Tests

```bash
bundle exec rake
```

### Code Style

This project uses [RuboCop](https://rubocop.org). Run it before submitting:

```bash
bundle exec rubocop
```

## Pull Request Guidelines

- Keep PRs focused on a single change
- Add tests for new functionality
- Update documentation if needed
- Ensure CI passes
