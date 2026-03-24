Feature: Run supervisor

  Scenario: Invalid config option
    Given a directory named "features/fixtures"
    And a file named "features/fixtures/supervisor_invalid.yaml" with:
    """
    default: invalid
    """
    When I run `rsmp supervisor -c features/fixtures/supervisor_invalid.yaml`
    Then the output should contain "Invalid configuration"
    Then the output should contain "/default"
    Then the output should contain "expected object, got string"
