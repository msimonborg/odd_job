defmodule OddJob.Pool do
  @moduledoc """
  The `OddJob.Pool` is a `GenServer` that manages the assignments given to the pool workers.

  The pool receives jobs and assigns them to available workers. If all workers in a pool are
  currently busy then the pool adds the new jobs to a FIFO queue to be processed as workers
  become available.
  """
  @moduledoc since: "0.3.0"
  use GenServer
  alias OddJob.Job
  alias OddJob.Pool

  @spec __struct__ :: OddJob.Pool.t()
  defstruct [:id, :pool, workers: [], assigned: [], jobs: []]

  @typedoc """
  The `OddJob.Pool` struct holds the state of the job pool.

    * `:id` is an atom representing the registered name of the pool process
    * `:pool` is an atom representing the name of the job pool
    * `:workers` is a list of the active worker `pid`s, whether they are busy working or not
    * `:assigned` is a list of the worker `pid`s that are currently assigned to a job
    * `:jobs` is a list of `OddJob.Job` structs representing the jobs that are queued to be performed
      when workers are available
  """
  @typedoc since: "0.3.0"
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
    GenServer.start_link(__MODULE__, opts, name: opts[:id])
  end

  @doc false
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: opts[:id])
  end

  @doc false
  @spec state(atom | pid) :: t
  def state(pool) do
    GenServer.call(pool, :state)
  end

  @doc false
  @spec monitor(atom | pid, atom | pid) :: :ok
  def monitor(pool, worker) do
    GenServer.cast(pool, {:monitor, worker})
  end

  @impl GenServer
  @spec init(any) :: {:ok, t}
  def init(opts) do
    state = struct(__MODULE__, opts)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:monitor, pid}, %Pool{workers: workers, jobs: []} = state) do
    Process.monitor(pid)
    {:noreply, %Pool{state | workers: workers ++ [pid]}}
  end

  def handle_cast(
        {:monitor, pid},
        %Pool{workers: workers, jobs: jobs, assigned: assigned} = state
      ) do
    Process.monitor(pid)
    workers = workers ++ [pid]
    assigned = assigned ++ [pid]
    [job | rest] = jobs
    GenServer.cast(pid, {:do_perform, job})
    {:noreply, %Pool{state | workers: workers, assigned: assigned, jobs: rest}}
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
         %Pool{jobs: jobs, assigned: assigned, workers: workers} = state
       ) do
    available = available_workers(workers, assigned)

    if available == [] do
      %Pool{state | jobs: jobs ++ new_jobs}
    else
      [worker | _rest] = available
      GenServer.cast(worker, {:do_perform, job})
      do_perform_many(rest, %Pool{state | assigned: assigned ++ [worker]})
    end
  end

  defp do_perform(job, %Pool{jobs: jobs, assigned: assigned, workers: workers} = state) do
    available = available_workers(workers, assigned)

    if available == [] do
      %Pool{state | jobs: jobs ++ [job]}
    else
      [worker | _rest] = available
      GenServer.cast(worker, {:do_perform, job})
      %Pool{state | assigned: assigned ++ [worker]}
    end
  end

  defp available_workers(workers, assigned), do: workers -- assigned

  @impl GenServer
  def handle_call(:complete, {pid, _}, %Pool{assigned: assigned, jobs: []} = state) do
    {:reply, :ok, %Pool{state | assigned: assigned -- [pid]}}
  end

  def handle_call(:complete, {worker, _}, %Pool{jobs: jobs} = state) do
    [new_job | rest] = jobs
    GenServer.cast(worker, {:do_perform, new_job})
    {:reply, :ok, %Pool{state | jobs: rest}}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %Pool{workers: workers, assigned: assigned} = state
      ) do
    Process.demonitor(ref, [:flush])
    workers = workers -- [pid]
    assigned = assigned -- [pid]
    {:noreply, %Pool{state | workers: workers, assigned: assigned}}
  end
end
