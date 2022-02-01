# OddJob
[![Hex pm](https://img.shields.io/hexpm/v/odd_job.svg?style=flat)](https://hex.pm/packages/odd_job)

Job pools for Elixir OTP applications, written in Elixir.

Use OddJob when you want to limit concurrency of background processing in your Elixir app. A good use case is forcing backpressure on calls to external APIs.

## Installation

The package can be installed by adding `odd_job` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:odd_job, "~> 0.2.2"}
  ]
end
```

## Getting Started
OddJob starts up a supervised job pool of 5 workers out of the box with no extra configuration.
The default name of this job pool is `:job`, and it can be sent work in the following way:

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

If you don't want OddJob to supervise any pools for you (including the default `:job` pool) then pass `false` to the `:default_pool` config key:

```elixir
config :odd_job, default_pool: false
```

To supervise your own job pools you can add them directly to the top level of your application's supervision tree:

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
name for the pool.

All of the above config options can be combined. You can have a default pool (with an optional custom name), extra pools in the OddJob supervision tree, and pools to be supervised by your own application.

Any pool can then be sent jobs by passing its unique name to one of the `OddJob` module's `perform` functions:

```elixir
job = OddJob.async_perform(:external_app, fn -> get_data(user) end)
# do something else
data = OddJob.await(job)
OddJob.perform(:email, fn -> send_email(user, data) end)
```

If a worker in the pool is available then the job will be performed right away. If all of the workers
are already assigned to other jobs then the new job will be added to a FIFO queue. Jobs in the queue are performed as workers become available.

Use `perform/2` for fire and forget jobs where you don't care about the results or if it succeeds. `async_perform/2` follows the async/await pattern in the `Task` module, and is useful when you need to retrieve the results and you care about success or failure.

Jobs can be scheduled for later with `perform_after/3` and `perform_at/3`:

```elixir
OddJob.perform_after(1_000_000, :job, fn -> clean_database() end) # accepts a timer in milliseconds

time = ~T[03:00:00.000000]
OddJob.perform_at(time, :job, fn -> verify_work_is_done() end) # accepts a valid Time or DateTime struct
```

The scheduling functions return a unique timer reference which can be read with `Process.read_timer` and
cancelled with `Process.cancel_timer`, which will cancel execution of the job itself. When the timer is up the job will be sent to the pool and can no longer be aborted.

Note that there is no guarantee that a scheduled job will be performed right away when the timer runs out. Like all jobs it is sent to the pool and if all workers are busy at that time then the job enters the queue to be performed when a worker is available.

## Documentation

For more usage, reference the [documentation](https://hexdocs.pm/odd_job).

