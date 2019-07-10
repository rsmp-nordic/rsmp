@watchdog @manual_connection @delay
Feature: Watchdog messages

  Scenario: Site should send watchdog messages
    When we start the supervisor and the site has connected
    Then we should receive 2 "Watchdog" messages within 2.0 seconds

  Scenario: Site should disconnect if we stop sending watchdog message
    When we start the supervisor and the site has connected
    And we turn off watchdog messages in the supervisor
    Then the site should disconnect within 3.0 seconds