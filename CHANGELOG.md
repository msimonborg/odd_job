# Changelog

## v0.3.2-dev

## v0.3.1

- Fix a mistake in documentation

## v0.3.0

- Remove `__using__` macro from `OddJob` module
- Change `to_perform_this` macro name to `perform_this`
- Add `:at` and `:after` keyword options to `perform_this` for scheduling jobs
- Fix bug that causes pool to overmonitor workers in the event of worker supervisor shutdown
- Isolate every `perform_after`/`perform_at` schedule in its own process so a scheduling failure doesn't destroy all schedules
- Change default pool name to `:job`
- Change config options
- Rename `queue` to `pool` in public functions and internal implementation
- Add another level of supervision for workers, so pool does not restart when workers are failing, which would cause the job queue to be lost.
- Improvements and fixes to documentation and tests