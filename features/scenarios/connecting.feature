Feature: Connection sequence
	
	Background: We're connected to a site


  Scenario: Connecting to a site
    Given we're the supervisor accepting communication from "AA+BBCCC=DDD"
    When we start listening on port 12111
    
    Then the site should connect within 2 seconds
    And we should have the following sequence of messages:
      | Version            |
      | Version            |
      | AggregatedStatus   |
