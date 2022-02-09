defmodule OddJob.Supervisor do
  @moduledoc """
  The `OddJob.Supervisor` is the supervisor at the top of a pool supervision tree, and is
  responsible for starting and supervising the `OddJob.Pool` and `OddJob.Pool.Worker`s.

  All of this module's public functions can be called using the `OddJob` namespace. See
  the `OddJob` documentation for usage.
  """
  @moduledoc since: "0.1.0"

  use Supervisor

  alias OddJob.Utils

  @type start_arg :: term | [{:name, term} | start_option]
  @type child_spec :: Supervisor.child_spec()
  @type start_option ::
          {:pool_size, non_neg_integer}
          | {:max_restarts, non_neg_integer}
          | {:max_seconds, non_neg_integer}

  @doc false
  @spec start_link(term, [start_option]) :: Supervisor.on_start()
  def start_link(name, opts \\ []) when is_list(opts) do
    init_opts = Keyword.delete(opts, :name)
    Supervisor.start_link(__MODULE__, [name, init_opts], name: Utils.supervisor_name(name))
  end

  @impl Supervisor
  def init([name, _opts] = args) do
    children = [
      {OddJob.Async.ProxySupervisor, name},
      {OddJob.Scheduler.Supervisor, name},
      {OddJob.Pool, name},
      {OddJob.Pool.Supervisor, args}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  def child_spec(opts) when is_list(opts) do
    {name, opts} = Keyword.pop!(opts, :name)

    opts
    |> super()
    |> Supervisor.child_spec(
      id: {OddJob, name},
      start: {__MODULE__, :start_link, [name, opts]}
    )
  end

  @spec child_spec(start_arg) :: child_spec
  def child_spec(name), do: child_spec(name: name)
end
