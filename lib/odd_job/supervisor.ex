defmodule OddJob.Supervisor do
  use Supervisor

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(name) do
    Supervisor.start_link(__MODULE__, name, name: id(name))
  end

  @impl true
  def init(name) do
    children = workers(name) ++ [{OddJob.Queue, %{id: queue_id(name), supervisor: id(name)}}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def child_spec(name) do
    %{
      id: id(name),
      start: {__MODULE__, :start_link, [name]},
      type: :supervisor
    }
  end

  defp id(name), do: :"odd_job_#{name}_sup"
  defp queue_id(name), do: :"odd_job_#{name}_queue"
  defp worker_id(name), do: :"odd_job_#{name}_worker"

  defp workers(name) do
    pool_size = Application.get_env(:odd_job, :pool_size, 5)

    for num <- 1..pool_size do
      id = worker_id("#{name}_#{num}")
      queue = queue_id(name)
      {OddJob.Worker, %{id: id, queue: queue}}
    end
  end
end
