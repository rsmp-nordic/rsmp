Secure RSMP development credentials
===================================

The sample Secure RSMP configs refer to credential files in this directory, but
the generated credential files themselves are intentionally ignored by git.

Generate local development credentials with:

```sh
bundle exec rsmp secure generate
```

These files are generated from the EDHOC suite0 test vector used by the local
`edhoc` gem. They are suitable for local prototype testing only. Do not use
these keys or credentials for deployment.

The sample configs use:

- `site-private.key`, `site.pub`, `site.cred` for the site side.
- `supervisor-private.key`, `supervisor.pub`, `supervisor.cred` for the supervisor side.
