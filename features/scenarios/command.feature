@command
Feature: Sending commands
  
  Background: We're connected to a site
    Given the supervisor settings "supervisor.yml"
    And the site settings "site.yml"
    When we start the server
    Then the site should connect within 2 seconds
    And the connection sequence should be complete within 1 seconds

  Scenario: Sending a command
    When we start collecting messages
    And we clear component data
    Then the received return values for component "AA+BBCCC=DDDEE002" should be empty

    When we send the command to component "AA+BBCCC=DDDEE002"
      | cCI   | n       | cO | v          |
      | MA104 | message |    | Rainbbows! |
    Then we should exchange these messages within 1 second
      | direction | message         |
      | out       | CommandRequest  |
      | in        | MessageAck      |
      | in        | CommandResponse |
      | out       | MessageAck      |
    And the "CommandResponse" message should contain the return values
      | cCI   | n       | v          | age    |
      | MA104 | message | Rainbbows! | recent |
    And the received return values for component "AA+BBCCC=DDDEE002" should be
      | cCI   | n       | v          | age    |
      | MA104 | message | Rainbbows! | recent |
