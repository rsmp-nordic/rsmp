This is a Ruby based repository contaning an implementation of RSMP (RoadSide Message Protocol), including:

- Ruby classes that can be used to build tests or other RSMP tools.
- Command-line tools for quickly running RSMP supervisors or sites and view messages exchanged.

It relies on the gem `rsmp_schema` to validate RSMP message using JSON schema.


Please follow these guidelines when contributing:

## Development Flow
- The Ruby version specified in .tool-versions must be used for running and validating code.
- All commands coming from gems msut be run from the bundle environment using `bundle exec ...`
- Before any commit, run `bundle exec rspec` to verify that all tests in the spec/ folder passes.
- Never add or commit files from vendor/.

## Repository Structure
- `bin/`: Main service entry points and executables
- `lib/`: Ruby source code
- `spec/`: RSpec test files for validating Ruby code
- `features/`: Cucumber test files for validating the CLI component
- `config/`: Configuration files used when running the 'rsmp' command line
- `documentation/`: Documentation

## Key Guidelines
- Follow Ruby best practices and idiomatic patterns.´
- Maintain existing code structure and organization.
- The code used the 'async' gem to run concurrent Ruby code. Follow existing async patterns already used in the project, also for testing.
- Code behaviour should adhere to the RSMP specifications defined at https://github.com/rsmp-nordic/rsmp_core.
- Write and verify rspec tests for new functionality.
- Document public APIs and complex logic. Suggest changes to the `documentation/` folder when appropriate.
- Don't commit example scripts.
- Be careful about claims like 'fully fiber-safe', unless it really has been tested.
- Prefer real classes over test doubles or mocks in tests and use async contexts to run sites and supervisors.
