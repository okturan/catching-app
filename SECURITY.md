# Security policy

## Supported version

Security fixes target the current `master` branch. The original 2021 classroom
deployment and historical commits are not maintained services.

## Reporting a vulnerability

Please use [GitHub's private vulnerability reporting form](https://github.com/okturan/catching-app/security/advisories/new)
instead of opening a public issue. Include the affected route or workflow, the
role of each test user, clear reproduction steps, and the impact you observed.

The maintainers especially want to know about:

- authentication, password-reset, session, or account-enumeration weaknesses;
- an authorization bypass between event organizers, invitees, and unrelated
  users;
- access to another user's events, invitations, availability, profile details,
  or account data;
- forged or inconsistent scheduling writes, including finalizing time slots as
  a non-organizer;
- injection, cross-site scripting, CSRF, unsafe redirects, file or secret
  exposure, and dependency or container vulnerabilities with a demonstrated
  impact.

Reports about the public member-name lookup are useful when they expose data
beyond the documented display-name search. Rate-limit observations without a
practical security impact and defects in seeded development accounts can be
filed as normal bugs.

Test only with accounts and data you control. Do not access another person's
event, availability, or account, and do not include real credentials or personal
data in the report. The maintainers will coordinate validation, remediation,
and disclosure through the private advisory.
