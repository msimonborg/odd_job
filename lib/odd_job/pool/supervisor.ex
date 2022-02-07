defmodule OddJob.Pool.Supervisor do
  @moduledoc false
  @moduledoc since: "0.3.0"

  use Supervisor
  alias OddJob.Utils

  def start_link([name, _opts] = args) do
    Supervisor.start_link(__MODULE__, args, name: Utils.pool_supervisor_name(name))
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
      id = Utils.pool_worker_name(name, num)
      pool_name = OddJob.Utils.pool_name(name)
      {OddJob.Pool.Worker, id: id, pool: name, pool_id: pool_name}
    end
  end
end
