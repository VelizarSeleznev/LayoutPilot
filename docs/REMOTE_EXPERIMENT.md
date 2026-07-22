# One-time remote experiment

This repository contains one deliberately narrow remote experiment used by a
build whose recipient has been told about the experiment before installation.

## Control manifest

The client reads `docs/remote/friend-prank.json` from the repository's `main`
branch. The app accepts exactly the compiled campaign ID, at most three
letter-only triggers, plain-text replacements up to 120 characters, and a fixed
allow-list of ordinary writing and messaging apps. It never accepts commands,
URLs, scripts, deletions, arbitrary settings, or application scopes from the
manifest.

The pack is handled once per installation. Changing the manifest after it has
been handled cannot modify or re-add its snippets. Set `active` to `false`
before the recipient launches the build to cancel it.

## Removal

Settings contains **Disable & Remove Remote Pack**. It removes only snippet IDs
recorded when the pack was applied, restores the Snippets module when safe, and
permanently disables further remote-pack checks for that installation.

## Anonymous usage events

The optional usage reporter sends only:

- replacement applied/rejected;
- a coarse correction mode;
- a coarse application category;
- app version and macOS major version;
- the rejected word only when it is 2-32 letters and the category is not a browser.

There is no device ID, IP captured by application code, exact bundle ID,
surrounding text, buffer, key code, layout ID, or replacement text in the
payload. The Vercel function validates the same allow-list before writing a
structured log line.

Run the endpoint validation tests with:

```sh
node --test telemetry-service/api/events.test.mjs
```
