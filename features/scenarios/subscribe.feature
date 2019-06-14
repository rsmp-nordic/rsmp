@subscribe
Feature: subscribing to status updates

  Background: We're connected to a site
    Given we focus on component "AA+BBCCC=DDDEE002"

  Scenario: Subcribe to status
    When we subscribe to the following statuses
      | cCI  | n      | uRt |
      | S001 | number | 1   |
    Then we should receive an acknowledgement
    And the status update should include the component id
    And the status update should include a timestamp that is within 1.0 seconds of our time
    And the status update should include the correct status code ids
    And the status update should include values
    And we start collecting messages
    And we should receive 1 "StatusUpdate" messages within 2 seconds
