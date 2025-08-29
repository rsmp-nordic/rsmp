# rsmp gem
This is a Ruby based repository contaning an implementation of RSMP (RoadSide Message Protocol), including:

- Ruby classes that can be used to build tests or other RSMP tools.
- Command-line tools for quickly running RSMP supervisors or sites and view messages exchanged.

It relies on the gem `rsmp_schema` to validate RSMP message using JSON schema.

Always reference these instructions first, and fall back to search or bash commands only when you encounter unexpected information that does not match the info here.

## Environment Setup
Copilot Agent runs in a minimal Docker container, NOT the devcontainer specified in .devcontainer.

Ruby will be available, but bundler and gems must be installed.
The Ruby version migh not match what's specified in .tool-versions, but it should still be possible to work in the repo.

### Install bundler
The bundler gem itself is usually included in modern Ruby distributions, but it's NOT included in the copilot agent container, so always install with:

```sh
gem install bundler --install-dir ~/.local/share/gem
```

Add gem executables to the PATH so they can be found:
```sh
export PATH="$HOME/.local/share/gem/bin:$PATH"
```

### Install Gems
Always use the bundler `path` config to install gems in the user’s local directory:
```sh
bundle config set --local path ~/.local/share/gem
bundle install
```

### Using Gem Executables
Always use 'bundle exec' to run executable from gems.


## Repository Structure
- `bin/`: Main service entry points and executables
- `lib/`: Ruby source code
- `spec/`: RSpec test files for validating Ruby code
- `features/`: Cucumber test files for validating the CLI component
- `config/`: Configuration files used when running the 'rsmp' command line
- `documentation/`: Documentation

## Key Guidelines
- Follow Ruby best practices and idiomatic patterns.
- Maintain existing code structure and organization.
- The code used the 'async' gem to run concurrent Ruby code. Follow existing async patterns already used in the project, also for testing.
- Code behaviour should adhere to the RSMP specifications defined at https://github.com/rsmp-nordic/rsmp_core.
- Write and verify rspec tests for new functionality.
- Document public APIs and complex logic. Update files in `documentation/` folder when appropriate.
- Don't commit example scripts.
- Prefer real classes over test doubles or mocks in tests and use aasync contexts to run sites and supervisors.
