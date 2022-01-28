defmodule OddJob.Queue do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: id(name))
  end

  @impl true
  def init(:ok) do
    {:ok, []}
  end

  def child_spec(name) do
    %{id: id(name), start: {OddJob.Queue, :start_link, [name]}}
  end

  defp id(name), do: :"odd_job_#{name}_queue"
end
