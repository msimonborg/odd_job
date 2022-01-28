defmodule OddJob.Supervisor do
  use Supervisor

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(name) do
    Supervisor.start_link(__MODULE__, name, name: id(name))
  end

  @impl true
  def init(name) do
    children = [
      {OddJob.Queue, name},
      {OddJob.Worker, name}
    ]

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
end
