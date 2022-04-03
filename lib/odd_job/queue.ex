defmodule OddJob.Queue do
  @moduledoc """
  The `OddJob.Queue` is a `GenServer` that manages the assignments given to the pool workers.

  The `queue` receives jobs and assigns them to available workers. If all workers in a pool are
  currently busy then new jobs are added to a FIFO queue to be processed as workers
  become available.
  """
  @moduledoc since: "0.4.0"

  @doc false
  use GenServer

  import OddJob, only: [is_enumerable: 1]

  alias OddJob.{Job, Pool.Worker, Utils}

  @spec __struct__ :: OddJob.Queue.t()
  defstruct [:pool, workers: [], assigned: [], jobs: []]

  @typedoc """
  The `OddJob.Queue` struct holds the state of the job queue.

    * `:pool` is a term representing the name of the job pool that the `queue` belongs to

    * `:workers` is a list of the active worker `pid`s, whether they are busy working or not

    * `:assigned` is a list of the worker `pid`s that are currently assigned to a job

    * `:jobs` is a list of `OddJob.Job` structs representing the jobs that are queued to be performed
      when workers are available
  """
  @typedoc since: "0.3.0"
  @type t :: %__MODULE__{
          pool: atom,
          workers: [pid],
          assigned: [pid],
          jobs: [job]
        }

  @type job :: Job.t()
  @type queue :: {:via, Registry, {OddJob.Registry, {atom, :queue}}}
  @type worker :: pid

  # <---- Client API ---->

  @doc false
  def start_link(pool_name) do
    GenServer.start_link(__MODULE__, pool_name, name: Utils.queue_name(pool_name))
  end

  @doc false
  @spec perform(queue, function | job) :: :ok
  def perform(queue, function) when is_function(function, 0),
    do: perform(queue, %Job{function: function, owner: self()})

  def perform(queue, job),
    do: GenServer.cast(queue, {:perform, job})

  @doc false
  @spec perform_many(queue, [job]) :: :ok
  def perform_many(queue, jobs) when is_list(jobs),
    do: GenServer.cast(queue, {:perform_many, jobs})

  @doc false
  @spec perform_many(queue, list | map, function) :: :ok
  def perform_many(queue, collection, function)
      when is_enumerable(collection) and is_function(function, 1) do
    jobs =
      for member <- collection do
        %Job{function: fn -> function.(member) end, owner: self()}
      end

    perform_many(queue, jobs)
  end

  @doc false
  @spec state(queue) :: t
  def state(queue),
    do: GenServer.call(queue, :state)

  @doc false
  @spec monitor_worker(queue, worker) :: :ok
  def monitor_worker(queue, worker) when is_pid(worker),
    do: GenServer.cast(queue, {:monitor, worker})

  @doc false
  @spec request_new_job(queue, worker) :: :ok
  def request_new_job(queue, worker),
    do: GenServer.cast(queue, {:request_new_job, worker})

  # <---- Callbacks ---->

  @impl GenServer
  @spec init(atom) :: {:ok, t}
  def init(pool_name) do
    state = struct(__MODULE__, pool: pool_name)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:monitor, pid}, %{workers: workers, jobs: []} = state) do
    Process.monitor(pid)
    {:noreply, %{state | workers: workers ++ [pid]}}
  end

  def handle_cast({:monitor, worker}, state) do
    Process.monitor(worker)
    workers = state.workers ++ [worker]
    assigned = state.assigned ++ [worker]
    [job | rest] = state.jobs
    Worker.perform(worker, job)
    {:noreply, %{state | workers: workers, assigned: assigned, jobs: rest}}
  end

  def handle_cast({:request_new_job, worker}, %{jobs: []} = state) do
    {:noreply, %{state | assigned: state.assigned -- [worker]}, _timeout = 10_000}
  end

  def handle_cast({:request_new_job, worker}, state) do
    [job | rest] = state.jobs
    Worker.perform(worker, job)
    {:noreply, %{state | jobs: rest}, _timeout = 10_000}
  end

  def handle_cast({:perform, job}, state) do
    state = do_perform(job, state)
    {:noreply, state}
  end

  def handle_cast({:perform_many, jobs}, state) do
    state = do_perform_many(jobs, state)
    {:noreply, state}
  end

  defp do_perform(job, %{jobs: jobs, assigned: assigned, workers: workers} = state) do
    available = available_workers(workers, assigned)

    if available == [] do
      %{state | jobs: jobs ++ [job]}
    else
      [worker | _rest] = available
      Worker.perform(worker, job)
      %{state | assigned: assigned ++ [worker]}
    end
  end

  defp do_perform_many([], state), do: state

  defp do_perform_many([job | rest] = new_jobs, state) do
    assigned = state.assigned
    available = available_workers(state.workers, assigned)

    if available == [] do
      %{state | jobs: state.jobs ++ new_jobs}
    else
      [worker | _rest] = available
      Worker.perform(worker, job)
      do_perform_many(rest, %{state | assigned: assigned ++ [worker]})
    end
  end

  defp available_workers(workers, assigned),
    do: workers -- assigned

  @impl GenServer
  def handle_call(:state, _from, state),
    do: {:reply, state, state}

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    Process.demonitor(ref, [:flush])
    workers = state.workers -- [pid]
    assigned = state.assigned -- [pid]
    {:noreply, %{state | workers: workers, assigned: assigned}}
  end

  def handle_info(:timeout, state),
    do: {:noreply, state, :hibernate}
end
