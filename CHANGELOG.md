# Changelog

## 0.1.0
Initial release.

## 0.1.1
- include schema files in gem package

## 0.1.2
- add license and required Ruby version to gemspec

## 0.1.3
- supervisor returns SXL version from site and allows setting SXL version
- validate messages against configured SXL

## 0.1.4
- logger.dump returns string instead of printing directly

## 0.1.5
- fix logger settings and add file logging

## 0.1.6
- fix hiding IP/port in logs

## 0.1.7
- abort wait_for_status_response if ack not received
- supervisor option to stop after first session

## 0.1.8
- update schemas and validator support
- return site_id received from site
- validate component id in status requests

## 0.1.10
- fix subscription bug and improve connection/site id handling
- validate incoming messages against SXL, not just core
- send status update values as strings

## 0.1.11
- update example configs
- fix wait_for_site :any handling
- remove default component

## 0.1.12
- fix wait_for_status_update bug

## 0.1.13
- supervisor returns all supported RSMP versions
- TLC fixes including timer drift and status handling
- wait_for_status_update now returns a hash

## 0.1.17
- TLC updates to pass validator tests and respond to status requests
- schema updates and component config format changes
- add wait_for_alarm and regex support in wait_for_status_update

## 0.1.18
- proxy reliability and error handling improvements
- new and updated wait/collect methods
- schema updates and expanded TLC protocol support
- alarm acknowledge handling and status update fixes

## 0.1.20
- improved timeout handling and error resilience
- logging and config handling improvements
- core/clock handling updates in TLC

## 0.1.21
- collecting and notification refactors with storage limits
- handshake and connect flow improvements

## 0.1.22
- fix collect_status_updates_or_responses

## 0.1.23
- maintenance release

## 0.1.24
- ensure proxy stops cleanly
- stricter conditions when waiting for status/command responses

## 0.1.27
- default SXL set to TLC
- option to disable validation of outgoing messages
- CLI option to convert SXL
- schema and timeout updates

## 0.1.29
- config handling cleanup and better config error reporting
- initial support for yellow flash in TLC emulator

## 0.1.30
- remove debug output

## 0.1.31
- fix CLI supervisor option and restart interval

## 0.1.32
- fix timer option name

## 0.1.33
- remove unused wait methods and update wait_for_supervisor
- aggregated status collection option

## 0.1.34
- fix wait_for_aggregated_status m_id usage and spelling

## 0.1.35
- update rsmp_schemer and schemas

## 0.1.36
- lenient SXL version parsing (e.g. 1.0.7.extra)

## 0.1.37
- improve lenient SXL version handling

## 0.1.38
- update rsmp_schemer gem

## 0.1.39
- collector no longer waits when already done

## 0.1.40
- logger supports streams and color overrides

## 0.2
- use Async::Queue for sentinel errors

## 0.2.1
- remove debug code

## 0.2.2
- reuse proxies when reconnecting and initialize proxy state

## 0.2.3
- refactor collection of command responses and status updates

## 0.3.0
- wait methods return message and collector
- improved messaging when no site connects
- set fP to nil on connect

## 0.3.1
- maintenance release

## 0.3.2
- avoid multiple main components

## 0.3.3
- allow skipping validations

## 0.3.4
- fix validation skipping class name

## 0.3.5
- expect ack after sending and raise if not connected
- only send aggregated status if ready
- check for duplicated alarms

## 0.3.6
- auto-build components

## 0.3.7
- infer component type in SiteProxy
- support default plan when creating SignalGroup

## 0.3.8
- rename wait_for_alarm to collect_alarms and return true

## 0.3.9
- fix force detector logic in TLC

## 0.4.0
- add Query class and reorganize collection code

## 0.4.1
- fix collection string match and improve timeout messaging
- show match progress

## 0.4.2
- maintenance release

## 0.4.3
- adjust collection match logging

## 0.4.4
- fix collection match storage logic

## 0.4.5
- fix RSMP version option for supervisor guests
- collection supports extra items

## 0.4.6
- fix validation after core rejection and nil hash handling

## 0.5.0
- support prefix in logger and improve reject logging
- defer notifications and abort on schema error/disconnect
- error distribution improvements

## 0.5.1
- fix rejection of duplicate connections

## 0.5.2
- guard against repeated status values when uRt=0

## 0.5.3
- clear deferred notifications/actions on exceptions

## 0.5.4
- show collection progress on timeout
- simplify schema error output

## 0.5.5
- adjust logging whitespace

## 0.5.6
- logger refactor with configurable field widths

## 0.6.0
- temporary error notification disabling

## 0.6.1
- maintenance release

## 0.6.2
- fix component id in logs

## 0.6.3
- TLC emulator improvements and class split
- plan switching and dynamic bands support

## 0.6.4
- handle more connection error types
- log component id by default

## 0.6.5
- guard against alarm timestamp moving backwards

## 0.7.0
- ability to ignore message types in log

## 0.7.1
- fixes for empty signal plans, timestamps, and alarm ignores

## 0.7.2
- fix uncaught Timestamp exceptions

## 0.7.3
- adjust alarm ignore behavior

## 0.7.4
- fix subscriptions
- CLI option to show version

## 0.7.5
- fix status without changes sometimes being sent

## 0.8.0
- rework collection during connecting
- collector improvements

## 0.8.1
- wait() returns messages
- collector class renames and cleanup

## 0.8.2
- update state collector

## 0.8.3
- simplify status collectors

## 0.8.4
- refactor startup sequence handling
- support day tables and startup sequences

## 0.8.5
- update send_and_optionally_collect and add ok! method
- collect! raises if cancelled

## 0.8.6
- remove wait_for_acknowledgement and cleanup collector types

## 0.9.0
- async task refactor and removal of Wait module

## 0.9.1
- implement M0019
- CLI returns non-zero on failures
- improve Windows connection handling

## 0.9.2
- implement M0001 timeout

## 0.9.3
- add AlarmCollector and remove SiteProxy#collect_alarms

## 0.9.4
- fix input deactivation

## 0.9.5
- improve AlarmCollector filtering

## 0.9.6
- fix M0006 input index validation

## 0.9.7
- initial support for programming inputs
- add missing TimestampError class

## 0.9.8
- guard against empty inputs config

## 0.9.9
- fix M0019 input validation

## 0.9.10
- add TLC::Inputs class for managing TLC inputs

## 0.10.1
- preliminary support for sending alarms
- add DL2 component to config

## 0.11.0
- support regex matching in AlarmCollector

## 0.11.2
- improve collector logging

## 0.11.3
- improve collector logging with progress hash

## 0.11.4
- show nil instead of :anything in query result hash

## 0.11.5
- fix logging using abstract method in initializer

## 0.11.6
- fix collect logger

## 0.11.7
- handshake completes only after watchdogs are sent and acked

## 0.12.0
- component proxy support
- improve repeated status checks

## 0.12.1
- remove debug output

## 0.12.2
- fix input logic alarm activation

## 0.12.3
- update schemas for alarm suspend/resume

## 0.13.0
- maintain alarm states

## 0.13.1
- config option for ntsOId and xNId

## 0.13.2
- configure ntsOId/xNId on grouped objects

## 0.13.3
- fix nts mechanism

## 0.13.4
- maintenance release

## 0.13.5
- avoid issues with empty component settings

## 0.13.6
- set ntsOId in tlc config

## 0.13.7
- send active alarms on connect
- fix alarm handling

## 0.13.9
- require Ruby 3.0+
- update rsmp_schemer

## 0.14.0
- update rsmp_schemer and YAML→JSON schema converter
- include sOc in subscriptions

## 0.14.1
- validation now handled by rsmp_schema

## 0.14.2
- update rsmp_schema with better TLC SXL 1.1 support

## 0.14.3
- update rsmp gem

## 0.14.4
- fix alarm suspend/resume object creation

## 0.14.5
- update rsmp gem and use RSMP::Scheme helpers

## 0.14.6
- fix schema version helper usage

## 0.15.0
- update rsmp_schema
- provide SXL version to component handlers
- handle S0091 and S0092 for SXL 1.1

## 0.15.1
- block repeated status values until subscription ack
- handle M0022 and S0033
- update rsmp_schema

## 0.15.2
- update rsmp_schema and timers gem

## 0.16.0
- determine core version from initial version message for validation

## 0.16.1
- connection handling improvements

## 0.16.2
- supervisor proxy ready after handshake

## 0.16.3
- use latest SXL by default

## 0.16.4
- timeout adjustments for site connections

## 0.16.5
- fix SXL version parsing when configured as float

## 0.16.6
- update rsmp_schema

## 0.16.7
- validate using proxy core version instead of latest

## 0.16.8
- use q or ageState depending on core version
- rename rsmp_version to core_version

## 0.16.9
- update rsmp_schema, use q instead of ageState

## 0.17.0
- enable alarm validation in TLC config
- update gems

## 0.17.1
- fix version helper usage in TLC

## 0.17.2
- handle source attribute in status messages

## 0.17.4
- add wait after socket connect for Windows
- support M0023

## 0.18.0
- handle alarm acknowledgements

## 0.18.1
- reset alarm to unacknowledged when activating

## 0.18.2
- configure component in input programming

## 0.19.0
- warn instead of disconnecting when no watchdogs are received
- configure component in input programming

## 0.19.1
- update Ruby and gems
- update TLC config for programming components

## 0.19.2
- update TLC config to raise A0302

## 0.19.3
- respond to alarm acknowledge with aSp=Acknowledge

## 0.19.4
- fix alarm differ check

## 0.19.5
- don't set timestamp when creating alarm state

## 0.20.1
- async 2 upgrade fixes for reconnects and IO errors
- require newer Ruby versions

## 0.20.2
- fix wait_for_condition after async 2 upgrade

## 0.20.3
- supervisor_proxy responds to AlarmAcknowledge

## 0.20.4
- set age=undefined when component id is unknown

## 0.20.6
- update rsmp_schema
- only auto-add component when type can be inferred
- respond to unknown component with q=undefined

## 0.20.7
- update async gem to fix hanging queues

## 0.21.0
- proper support for M0013

## 0.22.0
- update rsmp schema for core 3.2.1 and TLC SXL 1.2
- update gems

## 0.23.0
- fix S0035 handling
- use Set for emergency routes

## 0.23.1
- fix S0014 enum and add S0006 deprecation warning

## 0.24.0
- support S0005 statusByIntersection (SXL 1.2)

## 0.25.0
- update rsmp_schema, use native boolean for sOc

## 0.25.1
- allow different cases in AlarmState#differ_from_message?

## 0.25.2
- update rsmp gem

## 0.25.3
- fix suspended/Suspended casing handling

## 0.26.0
- temporarily disable watchdog

## 0.26.1
- set emergencyStage to zero if no active route

## 0.27.0
- add clear_alarm_timestamps

## 0.27.1
- update Ruby and async gems

## 0.28.0
- update gems
- use TLC SXL 1.2.1 in emulator
- update Ruby version

## 0.28.1
- maintenance release

## 0.29.0
- update schemas to support core 3.2.2
- update gems

## 0.31.0
- rename Query to Matcher and refactor collectors/filters
- update docs on collection and distribution

## 0.32.0
- fix default SXL option
- show core and SXL versions when starting

## 0.32.2
- update Ruby to 3.3.5
- simplify core config to a single version

## 0.32.3
- maintenance release

## 0.32.4
- update rsmp_schema

## 0.32.5
- ensure compact JSON generation on all platforms

## 0.32.6
- update rsmp_schema to allow Alarm aS=inactive

## 0.32.7
- update schema

## 0.33.0
- support changing cycle time with M0018
- update rsmp_schema

## 0.33.1
- send aggregated se bools as strings for core <= 3.1.2

## 0.33.2
- handle empty component config

## 0.33.3
- update gems

## 0.33.4
- fix se bool handling and avoid mutating component values

## 0.34.0
- support TLC S0098

## 0.34.1
- update async gems

## 0.34.2
- update schema gem

## 0.34.3
- remove duplicate describe_progress

## 0.35.0
- update Ruby to 3.4 and update gems

## 0.35.1
- update rsmp_schema and gems
- send values in S0207

## 0.35.2
- set s to null when q is unknown/undefined
- show versions in schema errors

## 0.37.0
- migrate to latest async (#121)
- revise contribution guidelines and testing instructions

## 0.38.0
- add rubocop workflow
- code cleanup and lint fixes

## 0.39.0
- remove rubocop exclusions and fix warnings
- update to Ruby 4 and update gems
- add rubocop workflow

## 0.40.0
- more robust config handling with JSON schema validation
- update to Ruby 4 and update gems

## 0.40.1
- fix config normalization
- improve config schema validation