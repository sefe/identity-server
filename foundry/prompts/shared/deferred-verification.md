# Bootstrap generation and review contract

This run prepares automation for later execution. This explicit configuration takes
precedence over generic instructions requiring local test execution or a negative
probe before delivery. Select the languages and frameworks from repository evidence;
the application's language does not dictate the automation technology.

Deliver complete frameworks, meaningful API/UI tests, configuration templates,
setup instructions, GitHub Actions workflows, a work/usage report and a draft PR.
Credentials and deployed endpoints will be supplied after delivery. Document the
required inputs; their current absence is not a bootstrap blocker. Never invent
credentials or passing results, weaken assertions, or replace real tests with stubs.

Do not execute generated suites, local substitute suites, application startup or
negative probes during bootstrap. Dependency resolution and static artifact review
remain part of generation. Do not demand extra tests solely to satisfy a bootstrap
execution gate. Record test execution as not attempted and measured coverage as
unavailable; planned scenarios are not executed coverage.

Generated test workflows must use workflow_dispatch only until credentials and
environment configuration are supplied after delivery. Do not add push, pull_request,
schedule or workflow_run triggers that would run tests when bootstrap publishes its
branch or PR. Include explicit prerequisite checks for subsequent manual test runs.
