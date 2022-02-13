# Changelog

## v.0.4.1

### Improvements
- Hibernate `OddJob.Queue` after a 10 second timeout to trigger garbage collection and reduce
memory consumption
- Fix typo in CHANGELOG.md

## v0.4.0

### Changes
- `OddJob.child_spec/1` accepts a keyword list of options that must contain a `:name` key with
an atom value, plus optional overrides.
- Change `OddJob.supervisor_id` to `OddJob.pool_supervisor_name/1`
- Change `OddJob.supervisor` to `OddJob.pool_supervisor/1`
- Change `OddJob.pool_id` to `OddJob.queue_name/1`
- Change `OddJob.Async.ProxyServer` to `OddJob.Async.Proxy`
- In the `OddJob` module `perform/2`, `perform_many/3`, `async_perform/2`, `async_perform_many/3`, 
`perform_after/3`, `perform_many_after/4`, `perform_at/3`, `perform_many_at/4`, `queue/1`,
`queue_name/1`, `pool_supervisor/1`, `pool_supervisor_name/1`, and `workers/1` will now return 
`{:error, :not_found}` if the pool does not exist at the time of calling. 
- `OddJob.perform_at/3` now only accepts a DateTime struct as the first argument.
- Revert previous `pool` usage in functions to `queue`, and change `OddJob.Pool` to `OddJob.Queue`
- Default pool cannot be renamed.

### Additions
- New functions `perform_many/3`, `async_perform_many/3`, `perform_many_after/4`, and 
`perform_many_at/4` can more efficiently enqueue large batches of jobs
- New public function `OddJob.start_link/1` can be used to start OddJob pools
- `use OddJob.Pool` to create module based job pools with runtime configuration and custom start
options for the top level supervisor
- New options for `max_restarts` and `max_seconds` join `pool_size` as configuration for the worker 
supervisor
- Any pool can override the default config and have its own configuration
- Config can be set for user-supervised pools by passing an options list to the `OddJob` child spec
tuple: `{OddJob, name: :work, pool_size: 10}`, or to `OddJob.start_link/1` for module-based pools.

### Improvements
- Use `:via` process naming for dynamically named processes.
- Every pool supervises its own proxy supervisor and scheduler supervisor to increase isolation 
between pools.
- Better documentation about version history.
- Better module documentation.

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
- Isolate every `perform_after`/`perform_at` schedule in its own process so a scheduling failure 
doesn't destroy all schedules
- Change default pool name to `:job`
- Change config options
- Rename `queue` to `pool` in public functions and internal implementation
- Add another level of supervision for workers, so pool does not restart when workers are failing, 
which would cause the job queue to be lost.
- Improvements and fixes to documentation and tests