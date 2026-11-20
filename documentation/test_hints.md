# Supervisor test hints

This is an optional Test Hub convention, not part of RSMP Core. A simulated site
can request a documented scenario over its existing connection to a supervisor.
The supervisor performs the action using ordinary RSMP messages; the validator
checks the resulting exchange. There is no separate acknowledgement of the hint.

```ruby
supervisor_proxy.send_test_hint!('M0002.set_plan')
```

The proxy must be ready. The hint is sent immediately and is not buffered:

```json
{
  "mType": "rSMsg",
  "type": "MessageNotAck",
  "oMId": "00000000-0000-4000-8000-000000000000",
  "rea": "test: {\"scenario\":\"M0002.set_plan\"}"
}
```

The synthetic `oMId` has valid UUID-v4 syntax, but deliberately does not refer to
an earlier message. An all-zero UUID or empty string would fail the existing
schemas. No message schema changes are required. Ordinary rejections, including
SXL hints responding to real Version messages, retain their normal handling.

## Enabling the Gem supervisor

Handling is disabled by default. Enable it only for simulated sites used for
testing, preferably in a site-specific entry:

```yaml
sites:
  RN+SI0001:
    test_hints: true
    sxls:
      tlc: '1.2.1'
    components:
      main:
        TC:
```

The receiver requires both the synthetic ID and the `test: ` prefix. Malformed
or unknown scenarios fall back to ordinary unmatched-acknowledgement handling;
they do not trigger actions. Requests before the connection is ready are ignored.
All actions target the main component of the requesting connection. Hints cannot
select another site or inject an arbitrary message.

## Prototype scenarios

Scenario IDs are stable identifiers, independent of Sus descriptions and paths.
Both scenarios require a negotiated TLC SXL and a main component matching the simulated site's main component.

| Scenario | Required exchange |
| --- | --- |
| `M0002.set_plan` | Send M0002, then acknowledge the site's CommandResponse. The test checks the message sequence, command code and acknowledgement ID, with normal message validation. The supervisor chooses the command arguments; the hint contains only the scenario ID. |
| `S0014.subscribe_once` | Subscribe to S0014, acknowledge the first matching StatusUpdate, then unsubscribe from the same component and status fields. The site acknowledges the unsubscribe normally. |

The Gem supervisor prototype selects plan 1 using security code `2222`, matching
the validator’s bundled simulated-site configuration. Other supervisors can choose
any arguments accepted by the configured site. For S0014, the Gem supervisor
subscribes to `status` with `uRt="1"` and includes `sOc=false` starting with Core 3.1.5.
Other supervisors can choose their own subscription settings.

Values use the wire representation required by the negotiated versions. Both
scenarios work with the prototype's tested Core 3.1.2–3.3.0/TLC combinations.
Only these two scenarios are implemented; this is not a general command API.

With `test_scenarios: true` in its supervisor test config, the validator runs all
scenarios applicable to the negotiated Core/SXL versions and expects them all to
pass. Setting it to `false` or omitting it skips the hint-driven tests. An enabled
scenario that receives no expected message fails on timeout; a malformed exchange
fails validation.
