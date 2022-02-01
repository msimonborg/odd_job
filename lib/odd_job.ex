defmodule OddJob do
  @moduledoc """
  Job pools for Elixir OTP applications, written in Elixir.

  Use OddJob when you want to limit concurrency of background processing in your Elixir app.
  One possible use case is forcing backpressure on calls to external APIs.

  ## Installation

  The package can be installed by adding `odd_job` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
  [
    {:odd_job, "~> 0.2.2"}
  ]
  end
  ```

  ## Getting started

  OddJob automatically starts up a supervised job pool of 5 workers out of the box with no extra
  configuration. The default name of this job pool is `:job`, and it can be sent work in the following way:

  ```elixir
  OddJob.perform(:job, fn -> do_some_work() end)
  ```

  The default pool can be customized in your config if you want to change the name or pool size:

  ```elixir
  config :odd_job,
    default_pool: :work,
    pool_size: 10 # this changes the size of all pools in your application, defaults to 5
  ```

  You can also add extra pools to be supervised by the OddJob application supervision tree:

  ```elixir
  config :odd_job,
    extra_pools: [:email, :external_app]
  ```

  If you don't want OddJob to supervise any pools for you (including the default `:job` pool) then
  pass `false` to the `:default_pool` config key:

  ```elixir
  config :odd_job, default_pool: false
  ```

  ## Supervising job pools

  To supervise your own job pools you can add a tuple in the form of `{OddJob, name}` (where `name` is an atom)
  directly to the top level of your application's supervision tree or any other list of child specs for a supervisor:

  ```elixir
  defmodule MyApp.Application do
    use Application

    def start(_type, _args) do

      children = [
        {OddJob, :email},
        {OddJob, :external_app}
      ]

      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  ```

  The tuple `{OddJob, :email}` will return a child spec for a supervisor that will start and supervise
  the `:email` pool. The second element of the tuple can be any atom that you want to use as a unique
  name for the pool. You can supervise as many pools as you want, as long as they have unique `name`s.

  All of the aforementioned config options can be combined. You can have a default pool (with an optional
  custom name), extra pools in the OddJob supervision tree, and pools to be supervised by your own application.

  ## Basic usage and async/await

  A job pool can be sent jobs by passing its unique name and an anonymous function to one of the `OddJob`
  module's `perform` functions:

  ```elixir
  job = OddJob.async_perform(:external_app, fn -> get_data(user) end)
  # do something else
  data = OddJob.await(job)
  OddJob.perform(:email, fn -> send_email(user, data) end)
  ```

  If a worker in the pool is available then the job will be performed right away. If all of the workers
  are already assigned to other jobs then the new job will be added to a FIFO queue. Jobs in the queue
  are performed as workers become available.

  Use `perform/2` for immediate fire and forget jobs where you don't care about the results or if it succeeds.
  `async_perform/2` and `await/1` follow the async/await pattern in the `Task` module, and are useful when
  you need to retrieve the results and you care about success or failure. Similarly to `Task.async/1`, async jobs
  will be linked and monitored by the caller (in this case, through a proxy). If either the caller or the job
  crash or exit, the other will crash or exit with the same reason.

  ## Scheduled jobs

  Jobs can be scheduled for later execution with `perform_after/3` and `perform_at/3`:

  ```elixir
  OddJob.perform_after(1_000_000, :job, fn -> clean_database() end) # accepts a timer in milliseconds

  time = ~T[03:00:00.000000]
  OddJob.perform_at(time, :job, fn -> verify_work_is_done() end) # accepts a valid Time or DateTime struct
  ```

  The scheduling functions return a unique timer reference which can be read with `Process.read_timer/1` and
  cancelled with `Process.cancel_timer/1`, which will cancel execution of the job itself. When the timer is
  up the job will be sent to the pool and can no longer be aborted.

  ```elixir
  ref = OddJob.perform_after(5000, :job, fn -> :will_be_canceled end)

  # somewhere else in your code
  if some_condition() do
    Process.cancel_timer(ref)
  end
  ```

  Note that there is no guarantee that a scheduled job will be performed right away when the timer runs out.
  Like all jobs it is sent to the pool and if all workers are busy at that time then the job enters the
  queue to be performed when a worker is available.

  For more usage, explore the [documentation](https://hexdocs.pm/odd_job).

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
      iex> :ok = OddJob.perform(:job, fn -> send(parent, :hello) end)
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

      iex> job = OddJob.async_perform(:job, fn -> :math.exp(100) end)
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

      iex> OddJob.async_perform(:job, fn -> :math.log(2.6881171418161356e43) end)
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

      iex> job1 = OddJob.async_perform(:job, fn -> 2 ** 2 end)
      iex> job2 = OddJob.async_perform(:job, fn -> 3 ** 2 end)
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

      timer_ref = OddJob.perform_after(5000, :job, fn -> deferred_job() end)
      Process.read_timer(timer_ref)
      #=> 2836 # time remaining before job enters the queue
      Process.cancel_timer(timer_ref)
      #=> 1175 # job has been cancelled

      timer_ref = OddJob.perform_after(5000, :job, fn -> deferred_job() end)
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
      OddJob.perform_at(time, :job, fn -> scheduled_job() end)
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

      iex> {pid, %OddJob.Queue{id: id}} = OddJob.queue(:job)
      iex> is_pid(pid)
      true
      iex> id
      :odd_job_job_queue
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

      iex> OddJob.queue_id(:job)
      :odd_job_job_queue
  """
  @spec queue_id(atom) :: atom
  defdelegate queue_id(pool), to: OddJob.Supervisor

  @doc """
  Returns the pid of the job `pool`'s supervisor.

  There is no guarantee that the process will still be alive after the results are returned,
  as it could exit or be killed or restarted at any time. Use `supervisor_id/1` to obtain
  the persistent ID of the supervisor.

  ## Examples

      OddJob.supervisor(:job)
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

      iex> OddJob.supervisor_id(:job)
      :odd_job_job_sup
  """
  @spec supervisor_id(atom) :: atom
  defdelegate supervisor_id(pool), to: OddJob.Supervisor, as: :id

  @doc """
  Returns a list of `pid`s for the specified worker pool.

  There is no guarantee that the processes will still be alive after the results are returned,
  as they could exit or be killed at any time.

  ## Examples

      OddJob.workers(:job)
      #=> [#PID<0.105.0>, #PID<0.106.0>, #PID<0.107.0>, #PID<0.108.0>, #PID<0.109.0>]
  """
  @spec workers(atom) :: [pid]
  def workers(pool) when is_atom(pool) do
    {_, %{workers: workers}} = queue(pool)
    workers
  end
end
