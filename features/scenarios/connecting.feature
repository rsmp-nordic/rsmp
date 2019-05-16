Feature: Connection sequence

  Scenario: Connecting
    Given we're the supervisor accepting communication from "AA+BBCCC=DDD"

    When we start listening on port 12111

    Then the site should connect within 5 seconds
    And the connection sequence should complete within 10 seconds
    And we should have the following sequence of messages:
      | Version            |
      | Version            |
      | Watchdog           |
      | Watchdog           |
      | AggregatedStatus   |
