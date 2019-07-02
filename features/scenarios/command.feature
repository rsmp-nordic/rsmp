@command
Feature: Sending commands

  Background: We're connected to a site
    Given we focus on component "AA+BBCCC=DDDEE002"

  Scenario: Sending a command
    When we send the following command request
      | cCI   | n       | cO | v          |
      | MA104 | message |    | Rainbbows! |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

  Scenario: Sending a command with special values
    When we send the following command request
      | cCI   | n       | cO | v |
      | MA104 | message |    |   |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI   | n       | cO | v      |
      | MA104 | message |    | æåøÆÅØ |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI   | n       | cO | v             |
      | MA104 | message |    | \/<>''""?:;., |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI   | n       | cO | v        |
      | MA104 | message |    | \n\r\t\f |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

  Scenario: Sending invalid commands
    When we send the following command request
      | cCI   | n        | cO | v          | bad |
      | MM104 | messsage |    | Rainbbows! | 1   |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI   | n        | v          |
      | MM104 | messsage | Rainbbows! |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI | n        | cO | v          |
      | bad | messsage |    | Rainbbows! |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI | n        | cO | v          |
      |     | messsage |    | Rainbbows! |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI   | n     | cO | v          |
      | MA104 | wrong |    | Rainbbows! |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response

    When we send the following command request
      | cCI   | n       | cO  | v          |
      | MA104 | message | bad | Rainbbows! |
    Then we should receive an acknowledgement
    And we should receive a command response within 1 second
    And same values should be returned in the command response
