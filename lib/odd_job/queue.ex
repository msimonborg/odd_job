defmodule OddJob.Queue do
  use GenServer
  alias OddJob.Job

  defstruct [:id, :supervisor, workers: [], assigned: [], jobs: []]

  @type t :: %__MODULE__{
          id: atom,
          supervisor: atom,
          workers: [pid],
          assigned: [pid],
          jobs: [job]
        }

  @type job :: Job.t()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts.id)
  end

  def child_spec(opts) do
    %{id: opts.id, start: {OddJob.Queue, :start_link, [opts]}}
  end

  @spec state(atom | pid | {atom, any} | {:via, atom, any}) :: t
  def state(queue) do
    GenServer.call(queue, :state)
  end

  @impl true
  @spec init(any) :: {:ok, t}
  def init(opts) do
    GenServer.cast(self(), :monitor_workers)
    state = struct(__MODULE__, opts)
    {:ok, state}
  end

  @impl true
  def handle_cast(:monitor_workers, %{supervisor: supervisor} = state) do
    workers = monitor_workers(supervisor)
    {:noreply, %{state | workers: workers}}
  end

  @impl true
  def handle_cast({:monitor, pid}, %{workers: workers, jobs: []} = state) do
    Process.monitor(pid)
    {:noreply, %{state | workers: workers ++ [pid]}}
  end

  @impl true
  def handle_cast({:monitor, pid}, %{workers: workers, jobs: jobs, assigned: assigned} = state) do
    Process.monitor(pid)
    workers = workers ++ [pid]
    assigned = assigned ++ [pid]
    [job | rest] = jobs
    GenServer.cast(pid, {:do_perform, job})
    {:noreply, %{state | workers: workers, assigned: assigned, jobs: rest}}
  end

  @impl true
  def handle_call({:complete, _job}, {pid, _}, %{assigned: assigned, jobs: []} = state) do
    {:reply, :ok, %{state | assigned: assigned -- [pid]}}
  end

  @impl true
  def handle_call({:complete, _job}, {worker, _}, %{jobs: jobs} = state) do
    [new_job | rest] = jobs
    GenServer.cast(worker, {:do_perform, new_job})
    {:reply, :ok, %{state | jobs: rest}}
  end

  @impl true
  def handle_call(
        {:perform, fun},
        {from, _},
        %{jobs: jobs, assigned: assigned, workers: workers} = state
      ) do
    job = %Job{function: fun, owner: from}
    available = workers -- assigned

    if available == [] do
      {:reply, :ok, %{state | jobs: jobs ++ [job]}}
    else
      [worker | _rest] = available
      GenServer.cast(worker, {:do_perform, job})
      {:reply, :ok, %{state | assigned: assigned ++ [worker]}}
    end
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %{workers: workers, supervisor: supervisor, assigned: assigned} = state
      ) do
    Process.demonitor(ref, [:flush])
    workers = workers -- [pid]
    assigned = assigned -- [pid]
    check_for_new_worker(supervisor, workers)
    {:noreply, %{state | workers: workers, assigned: assigned}}
  end

  defp check_for_new_worker(supervisor, workers) do
    children =
      for {_, pid, :worker, [OddJob.Worker]} <- Supervisor.which_children(supervisor) do
        pid
      end

    unmonitored = children -- workers

    if unmonitored == [] do
      check_for_new_worker(supervisor, workers)
    else
      for pid <- unmonitored do
        GenServer.cast(self(), {:monitor, pid})
      end
    end
  end

  defp monitor_workers(supervisor) do
    for {_, pid, :worker, [OddJob.Worker]} <- Supervisor.which_children(supervisor) do
      Process.monitor(pid)
      pid
    end
  end
end
