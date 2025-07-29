This is a Ruby based repository contaning an implementation of RSMP (RoadSide Message Protocol), including:

- Ruby classes that can be used to build tests or other RSMP tools.
- Command-line tools for quickly running RSMP supervisors or sites and view messages exchanged.

Is relies on the gem `rsmp_schema` to validate RSMP message using JSON schema.


Please follow these guidelines when contributing:

## Development Flow
- The Ruby version specified in .tool-versions must be used for running and validating code.
- Before any commit, run `rspec` to verify that all tests pass.

## Repository Structure
- `bin/`: Main service entry points and executables
- `lib/`: Ruby source code
- `spec/`: RSpec test files for validating Ruby code
- `features/`: Cucumber test files for validating the CLI component
- `config/`: Configuration files used when running the 'rsmp' command line
- `documentation/`: Documentation

## Key Guidelines
1. Follow Ruby best practices and idiomatic patterns.
2. The code used the 'async' gem to run concurrent Ruby code. Follow ASync best practices and idiomatic patterns.
3. Maintain existing code structure and organization.
4. Code behaviour should adhere to the RSMP specifications defined at https://rsmp-nordic.org/specification/.
4. Write RSpec unit tests for new functionality.
5. Document public APIs and complex logic. Suggest changes to the `docs/` folder when appropriate
