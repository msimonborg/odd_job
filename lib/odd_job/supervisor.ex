defmodule OddJob.Supervisor do
  use Supervisor

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(name) do
    Supervisor.start_link(__MODULE__, name, name: id(name))
  end

  @impl true
  def init(name) do
    children = workers(name) ++ [{OddJob.Queue, name}]
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

  defp workers(name) do
    pool_size = Application.get_env(:odd_job, :pool_size, 5)

    for num <- 1..pool_size do
      {OddJob.Worker, "#{name}_#{num}"}
    end
  end
end
