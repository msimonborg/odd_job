# Changelog

## v0.4.0-dev

### Added
- New functions `perform_many/3` and `async_perform_many/3` can more efficiently enqueue large batches of jobs
- New public function `OddJob.start_link/1` can be used to dynamically start OddJob pools
- Configuration options for `max_restarts` and `max_seconds`
- Any pool can override the default config and have its own configuration
- Config can be set for user-supervised pools by passing an options list to the `OddJob` child spec
tuple: `{OddJob, name: :work, pool_size: 10}`

### Improved
- Better documentation about version history.

## v0.3.3

- Fix a typo in documentation.

## v0.3.2

- Improve documentation of `perform_this` macros.

## v0.3.1

- Fix a mistake in documentation

## v0.3.0

- Remove `__using__` macro from `OddJob` module
- Change `to_perform_this` macro name to `perform_this`
- Add `:at` and `:after` keyword options to `perform_this` for scheduling jobs
- Fix bug that causes pool to overmonitor workers in the event of worker supervisor shutdown
- Isolate every `perform_after`/`perform_at` schedule in its own process so a scheduling failure doesn't
destroy all schedules
- Change default pool name to `:job`
- Change config options
- Rename `queue` to `pool` in public functions and internal implementation
- Add another level of supervision for workers, so pool does not restart when workers are failing, which
would cause the job queue to be lost.
- Improvements and fixes to documentation and tests