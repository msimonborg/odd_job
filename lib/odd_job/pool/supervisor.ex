defmodule OddJob.Pool.Supervisor do
  @moduledoc """
  The `OddJob.Pool.Supervisor` supervises the pool of `OddJob.Pool.Worker`s.
  """
  @moduledoc since: "0.3.0"

  @doc false
  use Supervisor

  alias OddJob.Utils

  @doc false
  def start_link([name, _opts] = args) do
    opts = [
      name: Utils.pool_supervisor_name(name)
    ]

    Supervisor.start_link(__MODULE__, args, opts)
  end

  @impl Supervisor
  def init([name, opts]) do
    config = Application.get_all_env(:odd_job)
    default_pool_size = Keyword.get(config, :pool_size, 5)
    {pool_size, opts} = Keyword.pop(opts, :pool_size, default_pool_size)

    default_opts = [
      strategy: :one_for_one,
      max_restarts: Keyword.get(config, :max_restarts, 3),
      max_seconds: Keyword.get(config, :max_seconds, 5)
    ]

    children = workers(name, pool_size)
    opts = Keyword.merge(default_opts, opts)
    Supervisor.init(children, opts)
  end

  defp workers(name, pool_size) do
    for num <- 1..pool_size do
      {OddJob.Pool.Worker, id: num, pool: name}
    end
  end
end
