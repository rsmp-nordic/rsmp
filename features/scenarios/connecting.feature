Feature: Connection sequence
	
	Background: We're connected to a site


  Scenario: Connecting to a site
    Given we're the supervisor accepting communication from "AA+BBCCC=DDD"

    When we start listening on port 12111

    Then the site "AA+BBCCC=DDD" should connect within 2 seconds
    And the connection sequence should complete within 10 seconds
    And we should see the following sequence of messages:
      | message            |
      | Version            |
      | Version            |
      | Watchdog           |
      | Watchdog           |
      | AggregatedStatus   |
