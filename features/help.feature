Feature: Help

  Scenario: Displaying help
    When I run `rsmp help`
    Then the output should contain "options"
