Feature: Run site

	Background:
    Given I wait 1 seconds for a command to start up

  Scenario: Run with no options
    When I run `rsmp site` interactively
		And I send the signal "SIGINT" to the command started last
    Then the output should contain "Starting site RN+SI0001"
    Then the output should contain "Connecting to superviser at 127.0.0.1:12111"

  Scenario: Help option
    When I run `rsmp help site`
    Then the output should contain "Usage:"
    Then the output should contain "Options:"

  Scenario: Site id option
    When I run `rsmp site -i RN+SI0639` interactively
		And I send the signal "SIGINT" to the command started last
    Then the output should contain "Starting site RN+SI0639"

  Scenario: Supervisors option
    When I run `rsmp site -s 127.0.0.8:12118` interactively
		And I send the signal "SIGINT" to the command started last
    Then the output should contain "Connecting to superviser at 127.0.0.8:12118"

  Scenario: Config option
    Given a directory named "features/fixtures"
    And a file named "features/fixtures/site.yaml" with:
    """
    site_id: RN+SI0932
    """

		When I run `rsmp site -c features/fixtures/site.yaml` interactively
		And I send the signal "SIGINT" to the command started last
    Then the output should contain "Starting site RN+SI0932"

  Scenario: Bad config option
		When I run `rsmp site -c bad/path/site.yaml` interactively
    Then the output should contain "Error: Config bad/path/site.yaml not found"
