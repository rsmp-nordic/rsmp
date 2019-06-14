@status
Feature: Requesting status

  Background: We're connected to a site
    Given we focus on component "AA+BBCCC=DDDEE002"

  Scenario: Request status
    When we request the following statuses
      | cCI  | n      |
      | S001 | number |
    Then we should receive an acknowledgement
    And the status response should include the component id
    And the status response should include a timestamp that is within 1.0 seconds of our time
    And the status response should include the correct status code ids
    And the status response should include values
