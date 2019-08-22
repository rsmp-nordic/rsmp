Feature: Run site

  Scenario: Run with no options
    When I run `rsmp site`
    Then the output should contain "Starting site"

  Scenario: Port option
    When I run `rsmp site --port 12117`
    Then the output should contain "Starting site on port 12117"
