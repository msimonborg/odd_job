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

  alias OddJob.{Job, Utils}

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
  @type queue_name :: {:via, Registry, {OddJob.Registry, {atom, :queue}}}

  # <---- API ---->

  @doc false
  def start_link(pool_name) do
    GenServer.start_link(__MODULE__, pool_name, name: Utils.queue_name(pool_name))
  end

  @doc false
  @spec perform(queue_name, function) :: :ok
  def perform(queue, function) when is_function(function, 0) do
    job = %Job{function: function, owner: self()}
    GenServer.cast(queue, {:perform, job})
  end

  @doc false
  @spec perform_many(queue_name, list | map, function) :: :ok
  def perform_many(queue, collection, function)
      when is_enumerable(collection) and is_function(function, 1) do
    jobs =
      for member <- collection do
        %Job{function: fn -> function.(member) end, owner: self()}
      end

    GenServer.cast(queue, {:perform_many, jobs})
  end

  @doc false
  @spec state(queue_name) :: t
  def state(queue),
    do: GenServer.call(queue, :state)

  @doc false
  @spec monitor_worker(queue_name, pid) :: :ok
  def monitor_worker(queue, worker) when is_pid(worker),
    do: GenServer.cast(queue, {:monitor, worker})

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

  def handle_cast(
        {:monitor, pid},
        %{workers: workers, jobs: jobs, assigned: assigned} = state
      ) do
    Process.monitor(pid)
    workers = workers ++ [pid]
    assigned = assigned ++ [pid]
    [job | rest] = jobs
    GenServer.cast(pid, {:do_perform, job})
    {:noreply, %{state | workers: workers, assigned: assigned, jobs: rest}}
  end

  def handle_cast({:complete, worker}, %{assigned: assigned, jobs: []} = state) do
    {:noreply, %{state | assigned: assigned -- [worker]}, _timeout = 10_000}
  end

  def handle_cast({:complete, worker}, %{jobs: jobs} = state) do
    [new_job | rest] = jobs
    GenServer.cast(worker, {:do_perform, new_job})
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

  defp do_perform_many([], state), do: state

  defp do_perform_many(
         [job | rest] = new_jobs,
         %{jobs: jobs, assigned: assigned, workers: workers} = state
       ) do
    available = available_workers(workers, assigned)

    if available == [] do
      %{state | jobs: jobs ++ new_jobs}
    else
      [worker | _rest] = available
      GenServer.cast(worker, {:do_perform, job})
      do_perform_many(rest, %{state | assigned: assigned ++ [worker]})
    end
  end

  defp do_perform(job, %{jobs: jobs, assigned: assigned, workers: workers} = state) do
    available = available_workers(workers, assigned)

    if available == [] do
      %{state | jobs: jobs ++ [job]}
    else
      [worker | _rest] = available
      GenServer.cast(worker, {:do_perform, job})
      %{state | assigned: assigned ++ [worker]}
    end
  end

  defp available_workers(workers, assigned), do: workers -- assigned

  @impl GenServer
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %{workers: workers, assigned: assigned} = state
      ) do
    Process.demonitor(ref, [:flush])
    workers = workers -- [pid]
    assigned = assigned -- [pid]
    {:noreply, %{state | workers: workers, assigned: assigned}}
  end

  def handle_info(:timeout, state) do
    {:noreply, state, :hibernate}
  end
end
