# OddJob
[![Hex pm](https://img.shields.io/hexpm/v/odd_job.svg?style=flat)](https://hex.pm/packages/odd_job)
[![Coverage Status](https://coveralls.io/repos/github/msimonborg/odd_job/badge.svg?branch=main)](https://coveralls.io/github/msimonborg/odd_job?branch=main)
![build](https://github.com/msimonborg/odd_job/actions/workflows/elixir.yml/badge.svg)

Job pools for Elixir OTP applications, written in Elixir.

Use OddJob when you want to limit concurrency of background processing in your Elixir app. One possible use case is forcing backpressure on calls to external APIs.

  ## Installation

  The package can be installed by adding `odd_job` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
  [
    {:odd_job, "~> 0.3.1"}
  ]
  end
  ```

  ## Getting started

  OddJob automatically starts up a supervised job pool of 5 workers out of the box with no extra
  configuration. The default name of this job pool is `:job`, and it can be sent work in the following way:

  ```elixir
  OddJob.perform(:job, fn -> do_some_work() end)
  ```

  The default pool can be customized in your config if you want to change the name or pool size:

  ```elixir
  config :odd_job,
    default_pool: :work,
    pool_size: 10 # this changes the size of all pools in your application, defaults to 5
  ```

  You can also add extra pools to be supervised by the OddJob application supervision tree:

  ```elixir
  config :odd_job,
    extra_pools: [:email, :external_app]
  ```

  If you don't want OddJob to supervise any pools for you (including the default `:job` pool) then
  pass `false` to the `:default_pool` config key:

  ```elixir
  config :odd_job, default_pool: false
  ```

  ## Supervising job pools

  To supervise your own job pools you can add a tuple in the form of `{OddJob, name}` (where `name` is an atom)
  directly to the top level of your application's supervision tree or any other list of child specs for a supervisor:

  ```elixir
  defmodule MyApp.Application do
    use Application

    def start(_type, _args) do

      children = [
        {OddJob, :email},
        {OddJob, :external_app}
      ]

      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  ```

  The tuple `{OddJob, :email}` will return a child spec for a supervisor that will start and supervise
  the `:email` pool. The second element of the tuple can be any atom that you want to use as a unique
  name for the pool. You can supervise as many pools as you want, as long as they have unique `name`s.

  All of the aforementioned config options can be combined. You can have a default pool (with an optional
  custom name), extra pools in the OddJob supervision tree, and pools to be supervised by your own application.

  ## Basic usage and async/await

  A job pool can be sent jobs by passing its unique name and an anonymous function to one of the `OddJob`
  module's `perform` functions:

  ```elixir
  job = OddJob.async_perform(:external_app, fn -> get_data(user) end)
  # do something else
  data = OddJob.await(job)
  OddJob.perform(:email, fn -> send_email(user, data) end)
  ```

  If a worker in the pool is available then the job will be performed right away. If all of the workers
  are already assigned to other jobs then the new job will be added to a FIFO queue. Jobs in the queue
  are performed as workers become available.

  Use `perform/2` for immediate fire and forget jobs where you don't care about the results or if it succeeds.
  `async_perform/2` and `await/1` follow the async/await pattern in the `Task` module, and are useful when
  you need to retrieve the results and you care about success or failure. Similarly to `Task.async/1`, async jobs
  will be linked and monitored by the caller (in this case, through a proxy). If either the caller or the job
  crash or exit, the other will crash or exit with the same reason.

  ## Scheduled jobs

  Jobs can be scheduled for later execution with `perform_after/3` and `perform_at/3`:

  ```elixir
  OddJob.perform_after(1_000_000, :job, fn -> clean_database() end) # accepts a timer in milliseconds

  time = ~T[03:00:00.000000]
  OddJob.perform_at(time, :job, fn -> verify_work_is_done() end) # accepts a valid Time or DateTime struct
  ```

  The scheduling functions return a unique timer reference which can be read with `Process.read_timer/1` and
  cancelled with `OddJob.cancel_timer/1`, which will cancel execution of the job itself *and* cause the scheduler process to exit. When the timer is up the job will be sent to the pool and can no longer be aborted.

  ```elixir
  ref = OddJob.perform_after(5000, :job, fn -> :will_be_canceled end)

  # somewhere else in your code
  if some_condition() do
    OddJob.cancel_timer(ref)
  end
  ```

  Note that there is no guarantee that a scheduled job will be performed right away when the timer runs out.
  Like all jobs it is sent to the pool and if all workers are busy at that time then the job enters the
  queue to be performed when a worker is available.

## Documentation

For more usage, explore the [documentation](https://hexdocs.pm/odd_job).

## Contributing

Pull requests are always welcome. Consider creating an issue first so we can have a discussion.

If you have an idea about how to improve OddJob please follow these steps:

1. Fork it
2. Clone it
3. Branch it
4. Code it
5. Document it (*especially public functions!!!*)
6. Test it (*and make sure they pass*)
7. Run `mix odd_job` to format, check test coverage (> 90% please), and run static code analysis
8. Commit it
9. Push it
10. Create a pull request

Thank you!

- Matt

## License

[MIT - Copyright (c) 2022 M. Simon Borg](https://github.com/msimonborg/odd_job/blob/main/LICENSE.txt)