# OddJob

Job pools for Elixir OTP applications, written in Elixir.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `odd_job` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:odd_job, "~> 0.1.0"}
  ]
end
```

## Getting Started
You can add job pools directly to the top level of your own application's supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do

    children = [
      {OddJob, :email},
      {OddJob, :task}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

The tuple `{OddJob, :email}` will return a child spec for a supervisor that will start and supervise
the `:email` pool. The second element of the tuple can be any atom that you want to use as a unique
name for the pool.

You can also configure `OddJob` to supervise your pools for you in a separate supervision tree.

In your `config.exs`:

```elixir
config :odd_job,
  supervise: [:email, :task]
```

You can also configure a custom pool size that will apply to all pools:

```elixir
config :odd_job, pool_size: 10 # the default value is 5
```

Now you can call on your pools to perform concurrent fire and forget jobs:

```elixir
OddJob.perform(:email, fn -> send_confirmation_email() end)
OddJob.perform(:task, fn -> update_external_application() end)
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/odd_job>.

