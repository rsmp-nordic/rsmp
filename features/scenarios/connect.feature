@connect @manual_connection
Feature: Connection sequence
  
  @3.1.1
  Scenario: Connecting to a site using RSMP 3.1.1
    When the supervisor setting 'rsmp_versions' is set to '["3.1.1"]'
    And we start the server
    Then the site should connect within 2 seconds
    And we should exchange these messages within 1 second
      | direction | message    |
      | in        | Version    |
      | out       | MessageAck |
      | out       | Version    |
      | in        | MessageAck |
      | in        | Watchdog   |
      | out       | MessageAck |
      | out       | Watchdog   |
      | in        | MessageAck |

  @3.1.2
  Scenario: Connecting to a site using RSMP 3.1.2
    When the supervisor setting 'rsmp_versions' is set to '["3.1.2"]'
    And we start the server
    Then the site should connect within 2 seconds
    And we should exchange these messages within 1 second
      | direction | message    |
      | in        | Version    |
      | out       | MessageAck |
      | out       | Version    |
      | in        | MessageAck |
      | in        | Watchdog   |
      | out       | MessageAck |
      | out       | Watchdog   |
      | in        | MessageAck |

  @3.1.3
  Scenario: Connecting to a site using RSMP 3.1.3
    When the supervisor setting 'rsmp_versions' is set to '["3.1.3"]'
    And we start the server
    Then the site should connect within 2 seconds
    And we should exchange these messages within 1 second
      | direction | message          |
      | in        | Version          |
      | out       | MessageAck       |
      | out       | Version          |
      | in        | MessageAck       |
      | in        | Watchdog         |
      | out       | MessageAck       |
      | out       | Watchdog         |
      | in        | MessageAck       |
      | in        | AggregatedStatus |
      | out       | MessageAck       |

  @3.1.4
  Scenario: Connecting to a site using RSMP 3.1.4
    When the supervisor setting 'rsmp_versions' is set to '["3.1.4"]'
    And we start the server
    Then the site should connect within 2 seconds
    And we should exchange these messages within 1 second
      | direction | message          |
      | in        | Version          |
      | out       | MessageAck       |
      | out       | Version          |
      | in        | MessageAck       |
      | in        | Watchdog         |
      | out       | MessageAck       |
      | out       | Watchdog         |
      | in        | MessageAck       |
      | in        | AggregatedStatus |
      | out       | MessageAck       |
