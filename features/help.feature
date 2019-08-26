Feature: Help

  Scenario: Displaying help
    When I run `rsmp help`
    Then it should pass with "Commands:"
