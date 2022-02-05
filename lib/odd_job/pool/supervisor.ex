defmodule OddJob.Pool.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link([name, opts]) do
    Supervisor.start_link(__MODULE__, [name, opts], name: id(name))
  end

  def init([name, opts]) do
    config = Application.get_all_env(:odd_job)
    default_pool_size = Keyword.get(config, :pool_size, 5)
    {pool_size, opts} = Keyword.pop(opts, :pool_size, default_pool_size)

    default_opts = [
      strategy: :one_for_one,
      max_restarts: Keyword.get(config, :max_restarts, 3),
      max_seconds: Keyword.get(config, :max_seconds, 5)
    ]

    opts = Keyword.merge(default_opts, opts)
    children = workers(name, pool_size)
    Supervisor.init(children, opts)
  end

  @spec id(atom | binary) :: atom
  def id(name) when is_atom(name) or is_binary(name), do: :"#{name}_pool_sup"

  defp workers(name, pool_size) do
    for num <- 1..pool_size do
      id = "#{name}_worker_#{num}"
      pool_id = OddJob.pool_id(name)
      {OddJob.Pool.Worker, %{id: id, pool: name, pool_id: pool_id}}
    end
  end
end
