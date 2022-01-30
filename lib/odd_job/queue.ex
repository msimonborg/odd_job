defmodule OddJob.Queue do
  use GenServer
  alias OddJob.Job
  alias OddJob.Queue, as: Q

  defstruct [:id, :supervisor, workers: [], assigned: [], jobs: []]

  @type t :: %__MODULE__{
          id: atom,
          supervisor: atom,
          workers: [pid],
          assigned: [pid],
          jobs: [job]
        }

  @type job :: Job.t()

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts.id)
  end

  @doc false
  def child_spec(opts) do
    %{id: opts.id, start: {OddJob.Queue, :start_link, [opts]}}
  end

  @doc false
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
  def handle_cast(:monitor_workers, %Q{supervisor: supervisor} = state) do
    workers = monitor_workers(supervisor)
    {:noreply, %Q{state | workers: workers}}
  end

  @impl true
  def handle_cast({:monitor, pid}, %Q{workers: workers, jobs: []} = state) do
    Process.monitor(pid)
    {:noreply, %Q{state | workers: workers ++ [pid]}}
  end

  @impl true
  def handle_cast({:monitor, pid}, %Q{workers: workers, jobs: jobs, assigned: assigned} = state) do
    Process.monitor(pid)
    workers = workers ++ [pid]
    assigned = assigned ++ [pid]
    [job | rest] = jobs
    GenServer.cast(pid, {:do_perform, job})
    {:noreply, %Q{state | workers: workers, assigned: assigned, jobs: rest}}
  end

  @impl true
  def handle_call(:complete, {pid, _}, %Q{assigned: assigned, jobs: []} = state) do
    {:reply, :ok, %Q{state | assigned: assigned -- [pid]}}
  end

  @impl true
  def handle_call(:complete, {worker, _}, %Q{jobs: jobs} = state) do
    [new_job | rest] = jobs
    GenServer.cast(worker, {:do_perform, new_job})
    {:reply, :ok, %Q{state | jobs: rest}}
  end

  @impl true
  def handle_call({:perform, job}, _from, state) do
    state = do_perform(job, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  defp do_perform(job, %Q{jobs: jobs, assigned: assigned, workers: workers} = state) do
    available = workers -- assigned

    if available == [] do
      %Q{state | jobs: jobs ++ [job]}
    else
      [worker | _rest] = available
      GenServer.cast(worker, {:do_perform, job})
      %Q{state | assigned: assigned ++ [worker]}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %Q{workers: workers, supervisor: supervisor, assigned: assigned} = state
      ) do
    Process.demonitor(ref, [:flush])
    workers = workers -- [pid]
    assigned = assigned -- [pid]
    check_for_new_worker(supervisor, workers)
    {:noreply, %Q{state | workers: workers, assigned: assigned}}
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
