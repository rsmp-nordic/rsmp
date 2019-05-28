Feature: Connection sequence
  
  Background: We're connected to a site
    Given the supervisor settings
      | site_id                 | RN+RS0001    |
      | port                    | 12111        |
      | rsmp_versions           | 3.1.3, 3.1.4 |
      | watchdog_interval       | 1            |
      | watchdog_timeout        | 2            |
      | acknowledgement_timeout | 2            |
      | logging                 | false        |
      | log_acknowledgements    | true         |
      | log_watchdogs           | true         |
      | store_messages          | true         |

  Scenario: Connecting to a site
    When we start the server
    Then the site "AA+BBCCC=DDD" should connect within 5 seconds
    And we should see the message sequence
      | Version          |
      | Version          |
      | AggregatedStatus |
