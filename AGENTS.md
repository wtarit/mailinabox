# Repository guide

## Project context

- This repository is an independently maintained Mail-in-a-Box fork. Prioritize this project's requirements, maintainability, and user experience; compatibility with upstream is not a requirement.
- The project provisions and manages a complete mail server appliance on Ubuntu. Changes can affect live mail delivery, DNS, authentication, TLS, backups, networking, and stored user data, so treat operational behavior and upgrades carefully.
- Setup must remain repeatable and idempotent. Re-running provisioning on an existing installation should converge on the intended state without losing user data or duplicating configuration.

## Repository map

- `setup/`: installation, migration, and service-configuration shell scripts.
- `management/`: Python management daemon, API and CLI logic, status checks, backups, DNS, mail configuration, and web UI templates.
- `conf/`: configuration templates installed onto managed systems.
- `tools/`: administrator and development utilities.
- `tests/`: integration and behavior checks, many of which expect a provisioned system.
- `api/`: API specification and generated documentation support.

## Development principles

- Follow existing patterns in the subsystem being changed, but improve structure when it materially reduces complexity or risk.
- Keep service configuration, management behavior, status checks, backup/restore behavior, and user-facing documentation consistent with one another.
- Preserve existing installations and user-managed data. When configuration or persistent state changes, provide safe defaults and an explicit migration path where needed.
- Keep secrets, credentials, private keys, mailbox contents, and other sensitive data out of logs, diffs, fixtures, and error messages.
- Prefer clear, direct implementations over extra abstraction. Avoid unrelated refactors unless they are necessary to make the requested change safe.
- Update nearby documentation, CLI help, API definitions, templates, and tests when behavior changes.

## Shell and Python conventions

- Shell scripts should fail clearly, quote expansions appropriately, and remain safe to run more than once.
- Python code targets Python 3.10 and follows the Ruff configuration in `pyproject.toml`.
- Treat files in `conf/` as templates: consider ownership, permissions, escaping, and whether local or generated values must survive reprovisioning.
- Do not assume network services or systemd are available in lightweight development environments. Separate pure logic tests from host-level integration checks when practical.

## Validation

- Run the narrowest relevant tests and linters first, then broaden validation in proportion to the change.
- For Python changes, use Ruff when available and at minimum compile changed modules with `python3 -m py_compile`.
- For shell changes, run `bash -n` and ShellCheck when available.
- Run relevant tests from `tests/`; clearly report checks that require a fully provisioned VM or server and could not be run locally.
- Before handoff, inspect `git diff --check`, the final diff, and `git status --short`. Do not modify or discard unrelated user changes.

## Working safely

- Use non-destructive commands and make focused edits. Never reset, overwrite, or remove unrelated work.
- Do not commit, push, deploy, restart services, or change a live system unless explicitly requested.
- For changes that could interrupt mail, DNS, login, TLS, or backups, explain the operational impact and include a rollback or recovery consideration.
