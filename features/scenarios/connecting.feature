@connect
Feature: Connection sequence
  
  Background: We're connected to a site
    Given the settings file "connecting.yml"

  Scenario: Connecting to a site
    When we start the server
    Then the site "AA+BBCCC=DDD" should connect within 2 seconds
    And we should exchange these messages within 2 seconds
      | in  | Version          |
      | out | MessageAck       |
      | out | Version          |
      | in  | MessageAck       |
      | in  | AggregatedStatus |
      | out | MessageAck       |
