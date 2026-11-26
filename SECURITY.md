# Security Policy

## Reporting a vulnerability

Do not open a public issue, pull request or discussion for a security problem.

Report it to Tyk's security team by email at **[security@tyk.io](mailto:security@tyk.io)**, as described in Tyk's
[coordinated vulnerability disclosure policy](https://tyk.io/responsible-disclosure/). That
policy covers Tyk products and services; it also sets out what to include, what Tyk does next,
and the rules for testing (use only test accounts, and do not share the problem with others until
it is fixed).

Please include:

- what is affected: a file in this repository, or a Tyk product and its version;
- what the problem is and how to reproduce it;
- the impact you think it could have.

## What belongs here

Report through the address above, not as an issue, anything such as:

- a configuration in this repository that exposes a credential, licence or private key, or
  publishes a service beyond the local machine without saying so;
- a script in this repository that runs or downloads something it should not;
- a default that disables a security control without a `# SECURITY:` or `# PROD:` marker saying so.

The configurations ship development defaults (secrets, passwords, TLS verification off) that are
marked for replacement before production. Those markers are documented behaviour, not a
vulnerability; a default that is unsafe and unmarked is.

A wrong fact, a broken link or a recipe that fails is not a security problem. Open an issue for
those.

## Supported versions

Fixes go into the `main` branch. Pull the latest `main` to get them.
