defmodule OddJob.Queue do
  @moduledoc """
  The job queue that manages the assignments given to the pool workers.
  """
  use GenServer
  alias OddJob.Job
  alias OddJob.Queue, as: Q

  @spec __struct__ :: OddJob.Queue.t()
  defstruct [:id, :pool, workers: [], assigned: [], jobs: []]

  @typedoc """
  The `OddJob.Queue` struct holds the state of the job queue.

    * `:id` is an atom representing the registered name of the queue process
    * `:pool` is an atom representing the name of the job pool
    * `:workers` is a list of the active worker `pid`s, whether they are busy working or not
    * `:assigned` is a list of the worker `pid`s that are currently assigned to a job
    * `:jobs` is a list of `OddJob.Job` structs representing the jobs that are queued to be performed
      when workers are available
  """
  @type t :: %__MODULE__{
          id: atom,
          pool: atom,
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

  @doc false
  @spec monitor(atom | pid, atom | pid) :: :ok
  def monitor(pool, worker) do
    GenServer.cast(pool, {:monitor, worker})
  end

  @impl true
  @spec init(any) :: {:ok, t}
  def init(opts) do
    ensure_all_monitored(opts.pool)
    state = struct(__MODULE__, opts)
    {:ok, state}
  end

  defp ensure_all_monitored(pool) do
    # The queue starts up before the workers, so on initial startup when no workers are registered
    # this function will do nothing. Workers are responsible for registering themselves and requesting
    # to be monitored by the queue in their init/1 callback. In the unlikely event of a crash/restart
    # of the queue itself, it should ensure that all living workers are monitored.
    Registry.dispatch(OddJob.WorkerRegistry, pool, fn workers ->
      for {worker, :worker} <- workers, do: monitor(self(), worker)
    end)
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
        %Q{workers: workers, assigned: assigned} = state
      ) do
    Process.demonitor(ref, [:flush])
    workers = workers -- [pid]
    assigned = assigned -- [pid]
    {:noreply, %Q{state | workers: workers, assigned: assigned}}
  end
end
