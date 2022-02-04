defmodule OddJob.Pool do
  @moduledoc false

  use Supervisor

  def start_link(name) do
    Supervisor.start_link(__MODULE__, name, name: id(name))
  end

  def init(name) do
    children = workers(name)
    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec id(atom | binary) :: atom
  def id(name) when is_atom(name) or is_binary(name), do: :"#{name}_pool_sup"

  defp workers(name) do
    pool_size = Application.get_env(:odd_job, :pool_size, 5)

    for num <- 1..pool_size do
      id = "#{name}_worker_#{num}"
      queue = OddJob.queue_id(name)
      {OddJob.Worker, %{id: id, pool: name, queue: queue}}
    end
  end
end
