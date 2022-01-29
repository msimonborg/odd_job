defmodule OddJob.Queue do
  use GenServer

  defstruct [:name, workers: [], jobs: []]

  @type t :: %__MODULE__{
          name: atom,
          workers: [pid],
          jobs: list
        }

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: id(name))
  end

  @impl true
  def init(name) do
    GenServer.cast(self(), {:monitor_workers, name})
    {:ok, %__MODULE__{name: name}}
  end

  def child_spec(name) do
    %{id: id(name), start: {OddJob.Queue, :start_link, [name]}}
  end

  @impl true
  def handle_cast({:monitor_workers, name}, state) do
    workers = monitor_workers(name)
    {:noreply, %{state | workers: workers}}
  end

  @impl true
  def handle_cast({:monitor, pid}, %{workers: workers} = state) do
    Process.monitor(pid)
    {:noreply, %{state | workers: workers ++ [pid]}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, %{name: name, workers: workers} = state) do
    Process.demonitor(ref, [:flush])
    workers = workers -- [pid]
    check_for_new_worker(name, workers)
    {:noreply, %{state | workers: workers}}
  end

  defp check_for_new_worker(name, workers) do
    children =
      for {_, pid, :worker, [OddJob.Worker]} <- Supervisor.which_children(supervisor(name)) do
        pid
      end

    unmonitored = children -- workers

    if unmonitored == [] do
      check_for_new_worker(name, workers)
    else
      for pid <- unmonitored do
        GenServer.cast(self(), {:monitor, pid})
      end
    end
  end

  defp id(name), do: :"odd_job_#{name}_queue"

  defp supervisor(name), do: :"odd_job_#{name}_sup"

  defp monitor_workers(name) do
    for {_, pid, :worker, [OddJob.Worker]} <- Supervisor.which_children(supervisor(name)) do
      Process.monitor(pid)
      pid
    end
  end
end
