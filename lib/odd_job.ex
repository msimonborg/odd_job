defmodule OddJob do
  @moduledoc """
  Job pools for Elixir OTP applications, written in Elixir.

  ## Usage

  You can add job pools directly to the top level of your own application's supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do

          children = [
            {OddJob, :email},
            {OddJob, :task}
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  The tuple `{OddJob, :email}` will return a child spec for a supervisor that will start and supervise
  the `:email` pool. The second element of the tuple can be any atom that you want to use as a unique
  name for the pool.

  You can also configure `OddJob` to supervise your pools for you in a separate supervision tree.

  In your `config.exs`:

      config :odd_job,
        supervise: [:email, :task]

  You can also configure a custom pool size that will apply to all pools:

      config :odd_job, pool_size: 10 # the default value is 5

  Now you can call on your pools to perform concurrent fire and forget jobs:

      OddJob.perform(:email, fn -> send_confirmation_email() end)
      OddJob.perform(:task, fn -> update_external_application() end)

  """
  alias OddJob.{Async, Job, Queue, Scheduler}

  @type job :: Job.t()
  @type queue :: Queue.t()
  @type child_spec :: %{
          id: atom,
          start: {OddJob.Supervisor, :start_link, [atom]},
          type: :supervisor
        }

  @doc false
  @spec child_spec(atom) :: child_spec
  defdelegate child_spec(name), to: OddJob.Supervisor

  @doc """
  Performs a fire and forget job.

  ## Examples

      iex> parent = self()
      iex> :ok = OddJob.perform(:work, fn -> send(parent, :hello) end)
      iex> receive do
      ...>   msg -> msg
      ...> end
      :hello
  """
  @spec perform(atom, function) :: :ok
  def perform(pool, fun) when is_atom(pool) and is_function(fun) do
    job = %Job{function: fun, owner: self()}
    GenServer.call(queue_id(pool), {:perform, job})
  end

  @doc """
  Performs an async job that can be awaited on for the result.

  Functions like `Task.async/1` and `Task.await/2`.

  ## Examples

      iex> job = OddJob.async_perform(:work, fn -> :math.exp(100) end)
      iex> OddJob.await(job)
      2.6881171418161356e43
  """
  @spec async_perform(atom, function) :: job
  def async_perform(pool, fun) when is_atom(pool) and is_function(fun) do
    Async.perform(pool, fun)
  end

  @doc """
  Awaits on an async job and returns the results.

  ## Examples

      iex> OddJob.async_perform(:work, fn -> :math.log(2.6881171418161356e43) end)
      ...> |> OddJob.await()
      100.0
  """
  @spec await(job, timeout) :: any
  def await(job, timeout \\ 5000) when is_struct(job, Job) do
    Async.await(job, timeout)
  end

  @doc """
  Awaits replies form multiple async jobs and returns them in a list.

  This function receives a list of jobs and waits for their replies in the given time interval.
  It returns a list of the results, in the same order as the jobs supplied in the `jobs` input argument.

  If any of the job worker processes dies, the caller process will exit with the same reason as that worker.

  A timeout, in milliseconds or `:infinity`, can be given with a default value of `5000`. If the timeout
  is exceeded, then the caller process will exit. Any worker processes that are linked to the caller process
  (which is the case when a job is started with `async_perform/2`) will also exit.

  This function assumes the jobs' monitors are still active or the monitor's :DOWN message is in the
  message queue. If any jobs have been demonitored, or the message already received, this function will
  wait for the duration of the timeout.

  ## Examples

      iex> job1 = OddJob.async_perform(:work, fn -> 2 ** 2 end)
      iex> job2 = OddJob.async_perform(:work, fn -> 3 ** 2 end)
      iex> [job1, job2] |> OddJob.await_many()
      [4, 9]
  """
  @spec await_many([job], timeout) :: [any]
  def await_many(jobs, timeout \\ 5000) when is_list(jobs) do
    Async.await_many(jobs, timeout)
  end

  @doc """
  Adds a job to the queue of the job `pool` after the given `timer` has elapsed.

  `timer` is an integer that indicates the number of milliseconds that should elapse before
  the job enters the queue. The timed message is executed under a separate supervised process,
  so if the caller crashes the job will still be performed. A timer reference is returned,
  which can be read with `Process.read_timer/1` or canceled with `Process.cancel_timer/1`.

  ## Examples

      timer_ref = OddJob.perform_after(5000, :work, fn -> deferred_job() end)
      Process.read_timer(timer_ref)
      #=> 2836 # time remaining before job enters the queue
      Process.cancel_timer(timer_ref)
      #=> 1175 # job has been cancelled

      timer_ref = OddJob.perform_after(5000, :work, fn -> deferred_job() end)
      Process.sleep(6000)
      Process.cancel_timer(timer_ref)
      #=> false # too much time has passed to cancel the job
  """
  @spec perform_after(integer, atom, function) :: reference
  def perform_after(timer, pool, fun)
      when is_integer(timer) and is_atom(pool) and is_function(fun) do
    Scheduler.perform_after(timer, pool, fun)
  end

  @doc """
  Adds a job to the queue of the job `pool` at the given `time`.

  `time` can be a `Time` or a `DateTime` struct. If a `Time` struct is received, then
  the job will be done the next time the clock strikes the given time. The timed message is executed
  under a separate supervised process, so if the caller crashes the job will still be performed.
  A timer reference is returned, which can be read with `Process.read_timer/1` or canceled with
  `Process.cancel_timer/1`.

  ## Examples

      time = Time.utc_now() |> Time.add(600, :second)
      OddJob.perform_at(time, :work, fn -> scheduled_job() end)
  """
  @spec perform_at(Time.t() | DateTime.t(), atom, function) :: reference
  def perform_at(time, pool, fun)
      when (is_struct(time, Time) or is_struct(time, DateTime)) and
             is_atom(pool) and is_function(fun) do
    Scheduler.perform_at(time, pool, fun)
  end

  @doc """
  Returns the pid and state of the job `pool`'s queue.

  ## Examples

      iex> {pid, %OddJob.Queue{id: id}} = OddJob.queue(:work)
      iex> is_pid(pid)
      true
      iex> id
      :odd_job_work_queue
  """
  @spec queue(atom) :: {pid, queue}
  def queue(pool) when is_atom(pool) do
    queue_id = queue_id(pool)
    state = queue_id |> Queue.state()
    pid = queue_id |> GenServer.whereis()
    {pid, state}
  end

  @doc """
  Returns the ID of the job `pool`'s queue.

  ## Examples

      iex> OddJob.queue_id(:work)
      :odd_job_work_queue
  """
  @spec queue_id(atom) :: atom
  defdelegate queue_id(pool), to: OddJob.Supervisor

  @doc """
  Returns the pid of the job `pool`'s supervisor.

  There is no guarantee that the process will still be alive after the results are returned,
  as it could exit or be killed or restarted at any time. Use `supervisor_id/1` to obtain
  the persistent ID of the supervisor.

  ## Examples

      OddJob.supervisor(:work)
      #=> #PID<0.239.0>
  """
  @spec supervisor(atom) :: pid
  def supervisor(pool) when is_atom(pool) do
    pool
    |> supervisor_id()
    |> GenServer.whereis()
  end

  @doc """
  Returns the ID of the job `pool`'s supervisor.

  ## Examples

      iex> OddJob.supervisor_id(:work)
      :odd_job_work_sup
  """
  @spec supervisor_id(atom) :: atom
  defdelegate supervisor_id(pool), to: OddJob.Supervisor, as: :id

  @doc """
  Returns a list of `pid`s for the specified worker pool.

  There is no guarantee that the processes will still be alive after the results are returned,
  as they could exit or be killed at any time.

  ## Examples

      OddJob.workers(:work)
      #=> [#PID<0.105.0>, #PID<0.106.0>, #PID<0.107.0>, #PID<0.108.0>, #PID<0.109.0>]
  """
  @spec workers(atom) :: [pid]
  def workers(pool) when is_atom(pool) do
    {_, %{workers: workers}} = queue(pool)
    workers
  end
end
