# rsmp gem
This is a Ruby based repository contaning an implementation of RSMP (RoadSide Message Protocol), including:

- Ruby classes that can be used to build tests or other RSMP tools.
- Command-line tools for quickly running RSMP supervisors or sites and view messages exchanged.

It relies on the gem `rsmp_schema` to validate RSMP message using JSON schema.

Always reference these instructions first, and fall back to search or bash commands only when you encounter unexpected information that does not match the info here.

## Development Flow
- Ruby and required gems are already installed by the action .github/copilot-setup-steps.yml, do not install them again.
- All gem executables must be run from the bundle environment using `bundle exec ...`
- Before any commit, run `bundle exec rspec` to verify that all tests pass.

## Repository Structure
- `bin/`: Main service entry points and executables
- `lib/`: Ruby source code
- `spec/`: RSpec test files for validating Ruby code
- `features/`: Cucumber test files for validating the CLI component
- `config/`: Configuration files used when running the 'rsmp' command line
- `documentation/`: Documentation

## Guidelines
- Follow Ruby best practices and idiomatic patterns.
- Maintain existing code structure and organization.
- Always use existing async patterns to handle concurrency, also in tests.
- Code behaviour should adhere to the RSMP specifications defined at https://github.com/rsmp-nordic/rsmp_core.
- Write and verify rspec tests for new functionality.
- Document public APIs and complex logic. Suggest changes to the `documentation/` folder when appropriate.
- Don't commit example scripts.
- Prefer real classes over test doubles or mocks in tests and use async contexts to run sites and supervisors.
- When reporting on progress, claims should be supported by tests or other data.
