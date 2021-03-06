defmodule OddJob.Pool.Supervisor do
  @moduledoc """
  The `OddJob.Pool.Supervisor` supervises the pool of `OddJob.Pool.Worker`s.
  """
  @moduledoc since: "0.3.0"

  @doc false
  use Supervisor

  alias OddJob.Utils

  @doc false
  @spec start_link({atom, keyword}) :: Supervisor.on_start()
  def start_link({name, _pool_opts} = start_arg),
    do: Supervisor.start_link(__MODULE__, start_arg, name: Utils.pool_supervisor_name(name))

  @impl Supervisor
  def init({name, pool_opts}) do
    config = Application.get_all_env(:odd_job)
    default_pool_size = Keyword.get(config, :pool_size, System.schedulers_online())
    {pool_size, start_opts} = Keyword.pop(pool_opts, :pool_size, default_pool_size)

    default_start_opts = [
      strategy: :one_for_one,
      max_restarts: Keyword.get(config, :max_restarts, 3),
      max_seconds: Keyword.get(config, :max_seconds, 5)
    ]

    children = workers(name, pool_size)
    start_opts = Keyword.merge(default_start_opts, start_opts)
    Supervisor.init(children, start_opts)
  end

  defp workers(name, pool_size) do
    for num <- 1..pool_size do
      {OddJob.Pool.Worker, id: num, pool: name}
    end
  end
end
