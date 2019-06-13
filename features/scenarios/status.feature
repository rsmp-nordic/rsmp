@status
Feature: Requesting status

  Background: We're connected to a site
    Given we focus on component "AA+BBCCC=DDDEE001"

  Scenario: Request status
    When we request the following statuses
      | cCI   | n |
      | S2001 |   |
    Then we should receive an acknowledgement
    And the status response should include the component id
    And the timestamp should be within 1.0 seconds of our time
    And values should be returned in the status response
