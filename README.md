# OddJob
[![Hex pm](https://img.shields.io/hexpm/v/odd_job.svg?style=flat)](https://hex.pm/packages/odd_job)
[![Hex docs](https://img.shields.io/badge/hex.pm-docs-blue)](https://hexdocs.pm/odd_job/api-reference.html)
[![Coverage Status](https://coveralls.io/repos/github/msimonborg/odd_job/badge.svg?branch=main)](https://coveralls.io/github/msimonborg/odd_job?branch=main)
![build](https://github.com/msimonborg/odd_job/actions/workflows/elixir.yml/badge.svg)

<!-- MDOC -->

Job pools for Elixir OTP applications, written in Elixir.

Use OddJob when you need to limit concurrency of background processing in your Elixir app, like forcing backpressure on
calls to databases or external APIs. OddJob is easy to use and configure, and provides functions for fire-and-forget jobs,
async/await calls where the results must be returned, and job scheduling. Job queues are stored in process memory so no
database is required.

## Installation

The package can be installed by adding `odd_job` to your list of dependencies in `mix.exs`:

```elixir
def deps do
[
  {:odd_job, "~> 0.4.0"}
]
end
```

## Getting started

After installation you can start processing jobs right away. OddJob automatically starts up a supervised job
pool of 5 workers out of the box with no configuration required. The default name of this job pool is `OddJob.Pool`,
and it can be sent work in the following way:

```elixir
OddJob.perform(OddJob.Pool, fn -> do_some_work() end)
```
You can skip ahead for more [usage](#usage), or read on for a guide to configuring your job pools.

## Configuration

The default pool can be customized in your config if you want to change the pool size:

```elixir
config :odd_job,
  pool_size: 10 # defaults to the number of schedulers online
```

If you are processing jobs that have a high chance of failure, you may want to customize the `max_restarts` and `max_seconds`
options to prevent all the workers in a pool from restarting if too many jobs are failing. These options
default to the `Supervisor` defaults (`max_restarts: 3, max_seconds: 5`) and can be overridden in your config:

```elixir
config :odd_job,
  pool_size: 10,
  max_restarts: 10,
  max_seconds: 2
```

### Extra pools

You can add extra pools to be supervised by the OddJob application supervision tree:

```elixir
config :odd_job,
  extra_pools: [MyApp.Email, MyApp.ExternalService]
```

By default, extra pools will be configured with the same options as your default pool. Luckily, extra pools
can receive their own list of overrides:

```elixir
config :odd_job,
  pool_size: 10,
  max_restarts: 5,
  extra_pools: [
    MyApp.Email, # MyApp.Email will use the defaults
    "MyApp.ExternalService": [ # the MyApp.ExternalService pool gets its own config
      pool_size: 5,
      max_restarts: 2
    ]
  ]
```

Next we'll see how you can [add job pools to your own application's supervision tree](#supervising-job-pools).
If you don't want OddJob to supervise any pools for you (including the default `OddJob.Pool`
pool) do not set a value for `:extra_pools` and pass `false` to the `:default_pool` config key:

```elixir
config :odd_job, default_pool: false
```

## Supervising job pools

You can dynamically start a new job pool linked to the current process by calling `OddJob.start_link/1`:

```elixir
{:ok, pid} = OddJob.start_link(name: MyApp.Email, pool_size: 10)
OddJob.perform(MyApp.Email, fn -> do_something() end)
#=> :ok
```

The first argument to the function is the name of the pool, the second argument is a keyword list
of options to configure the pool. See the `OddJob.start_link/1` documentation for more details.

In most cases you'll want to supervise your job pools, which you can do by adding a tuple in
the form of `{OddJob, options}` directly to the top level of your application's supervision 
tree or any other list of child specs for a supervisor:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do

    children = [
      {OddJob, name: MyApp.Email},
      {OddJob, name: MyApp.ExternalService}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

The tuple `{OddJob, name: MyApp.Email}` will return a child spec for a supervisor that will start 
and supervise the `MyApp.Email` pool. The second element of the tuple must be a keyword list of
options with a `:name` key and a unique `name` value as an atom. You can supervise as many pools as
you want, as long as they have unique names.

Any default configuration options listed in your `config.exs` will also apply to your own supervised
pools. You can override the config for any pool by specifying the configuration in your
child spec options:

```elixir
children = [
  # The MyApp.Email pool will use the default config:
  {OddJob, name: MyApp.Email},
  # The MyApp.ExternalService pool will not:
  {OddJob, name: MyApp.ExternalService, pool_size: 20, max_restarts: 10}
]
```

<!-- USINGDOC -->

## Module-based pools

You may want to configure your pool at runtime, or wrap your logic in a custom API. Module-based
pools are great for this. Invoking `use OddJob.Pool` defines a `child_spec/1` function that can be
used to start your pool under a supervisor.

Imagine you want to start a job pool with a dynamically configurable pool size and wrap it in
a client API:

```elixir
defmodule MyApp.Email do
  use OddJob.Pool

  def start_link(init_arg) do
    OddJob.start_link(name: __MODULE__, pool_size: init_arg)
  end

  # Client API

  def send_email(user) do
    OddJob.perform(__MODULE__, fn -> MyApp.Mailer.send(user) end)
  end
end
```

Now you can supervise your pool and set the pool size in a child spec tuple:

```elixir
children = [
  {MyApp.Email, 20}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

You can also skip the initial argument by passing `MyApp.Email` on its own:

```elixir
# in my_app/application.ex

children = [
  MyApp.Email # Same as {MyApp.Email, []}
]

Supervisor.start_link(children, strategy: :one_for_one)

# in my_app/email.ex

defmodule MyApp.Email do
  use OddJob.Pool

  def start_link(_init_arg) do
    OddJob.start_link(name: __MODULE__)
  end
end
```

For convenience, `use OddJob.Pool` automatically defines an overridable `start_link/1` function 
just like the one above, that ignores the initial argument and names the pool after the module, 
using the default configuration options. This means the above example is equivalent to:

```elixir
defmodule MyApp.Email do
  use OddJob.Pool
end
```

You can pass any supervision start options to `use OddJob.Pool`:

```elixir
use OddJob.Pool, restart: :transient, shutdown: :brutal_kill
```

The default options are the same as any `Supervisor`. See the `Supervisor` module for more info on
supervision start options.

<!-- USINGDOC -->

All of the previously mentioned config options can be combined. You can have a 
default pool, extra pools in the OddJob supervision tree, and pools to 
be supervised by your own application, all of which can either use the default config or their own 
overrides.

## Usage

A job pool can be sent jobs by passing its unique name and an anonymous function to one of the `OddJob`
module's `perform` functions:

```elixir
job = OddJob.async_perform(MyApp.ExternalService, fn -> get_data(user) end)
# do something else
data = OddJob.await(job)
OddJob.perform(MyApp.Email, fn -> send_email(user, data) end)
```

If a worker in the pool is available then the job will be performed right away. If all of the 
workers are already assigned to other jobs then the new job will be added to a FIFO queue. Jobs in 
the queue are performed as workers become available.

Use `perform/2` for immediate fire and forget jobs where you don't care about the results or if it 
succeeds. `async_perform/2` and `await/1` follow the async/await pattern in the `Task` module, and 
are useful when you need to retrieve the results and you care about success or failure. Similarly 
to `Task.async/1`, async jobs will be linked and monitored by the caller (in this case, through a 
proxy). If either the caller or the job crash or exit, the other will crash or exit with the same 
reason.

## Scheduled jobs

Jobs can be scheduled for later execution with `perform_after/3` and `perform_at/3`:

```elixir
OddJob.perform_after(1_000_000, OddJob.Pool, fn -> clean_database() end) # accepts a timer in milliseconds

time = DateTime.utc_now |> DateTime.add(60 * 60 * 24, :second) # 24 hours from now
OddJob.perform_at(time, OddJob.Pool, fn -> verify_work_is_done() end) # accepts a future DateTime struct
```

The scheduling functions return a unique timer reference which can be read with `Process.read_timer/
1` and cancelled with `OddJob.cancel_timer/1`, which will cancel execution of the job itself *and* 
clean up after itself by causing the scheduler process to exit. When the timer is up the job will 
be sent to the pool and can no longer be aborted.

```elixir
ref = OddJob.perform_after(5000, OddJob.Pool, fn -> :will_be_canceled end)

# somewhere else in your code
if some_condition() do
  OddJob.cancel_timer(ref)
end
```

Note that there is no guarantee that a scheduled job will be executed immediately when the timer 
runs out. Like all jobs it is sent to the pool and if all workers are busy then the job enters the 
queue to be performed as soon as a worker is available.

## License

[MIT - Copyright (c) 2022 M. Simon Borg](https://github.com/msimonborg/odd_job/blob/main/LICENSE.txt)

<!-- MDOC -->

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

Thank you! - [@msimonborg](https://github.com/msimonborg)