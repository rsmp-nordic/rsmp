@subscribe
Feature: subscribing to status updates

  Background: We're connected to a site
    Given we focus on component "AA+BBCCC=DDDEE002"

  @delay
  Scenario: Subcribe to status
    When we subscribe to the following statuses
      | sCI  | n      | uRt |
      | S001 | number | 1   |
    Then we should receive an acknowledgement
    And we should receive a status update within 1 second
    And the status update should include the component id
    And the status update should include a timestamp that is within 1.0 seconds of our time
    And the status update should include the correct status code ids
    And the status update should include values
    And we should receive 2 "StatusUpdate" messages within 2 seconds

    When we unsubscribe to the following statuses
      | sCI  | n      |
      | S001 | number |
    Then we should receive an acknowledgement
    And we should not receive a status update within 2 second
