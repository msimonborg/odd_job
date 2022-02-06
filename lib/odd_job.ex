defmodule OddJob do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)
             |> String.replace("#usage", "#module-usage")
             |> String.replace("#supervising-job-pools", "#module-supervising-job-pools")

  @moduledoc since: "0.1.0"

  alias OddJob.{Async, Job, Pool, Scheduler}

  @type job :: Job.t()
  @type pool :: Pool.t()
  @type start_arg :: OddJob.Supervisor.start_arg()
  @type start_option :: OddJob.Supervisor.start_option()
  @type child_spec :: OddJob.Supervisor.child_spec()

  @doc false
  @doc since: "0.4.0"
  defguard is_enumerable(term) when is_list(term) or is_map(term)

  @doc """
  A macro for creating jobs with an expressive DSL.

  `perform_this/2` works like `perform/2` except it accepts a `do` block instead of an anonymous function.

  ## Examples

  You must `import` or `require` `OddJob` to use macros:

      import OddJob

      perform_this :work do
        some_work()
        some_other_work()
      end

      perform_this :work, do: something_hard()
  """
  @doc since: "0.3.0"
  defmacro perform_this(pool, contents)

  defmacro perform_this(pool, do: block) do
    quote do
      OddJob.perform(unquote(pool), fn -> unquote(block) end)
    end
  end

  defmacro perform_this(pool, [{key, val}, {:do, block}]) do
    quote do
      perform_this(unquote(pool), [{unquote(key), unquote(val)}], do: unquote(block))
    end
  end

  @doc """
  A macro for creating jobs with an expressive DSL.

  `perform_this/3` accepts a single configuration option as the second argument that will control execution of
  the job. The available options provide the functionality of `async_perform/2`, `perform_at/3`,
  and `perform_after/3`.

  ## Options

    * `:async` - Passing the atom `:async` as the second argument before the `do` block creates an async
    job that can be awaited on. See `async_perform/2`.

    * `at: time` - Use this option to schedule the job for a specific `time` in the future. `time` must be
    a valid `Time` or `DateTime` struct. See `perform_at/3`.

    * `after: timer` - Use this option to schedule the job to perform after the given `timer` has elapsed. `timer`
    must be in milliseconds. See `perform_after/3`.

  ## Examples

      import OddJob

      time = ~T[03:00:00.000000]
      perform_this :work, at: time do
        scheduled_work()
      end

      perform_this :work, after: 5000, do: something_important()

      perform_this :work, :async do
        get_data()
      end
      |> await()

      iex> (perform_this :work, :async, do: 10 ** 2) |> await()
      100
  """
  @doc since: "0.3.0"
  defmacro perform_this(pool, option, contents)

  defmacro perform_this(pool, [{key, val}], do: block) do
    quote do
      OddJob.unquote(:"perform_#{key}")(unquote(val), unquote(pool), fn -> unquote(block) end)
    end
  end

  defmacro perform_this(pool, :async, do: block) do
    quote do
      OddJob.async_perform(unquote(pool), fn -> unquote(block) end)
    end
  end

  @doc """
  Returns a specification to start this module under a supervisor.

  ## Examples

      iex> :work |> OddJob.child_spec()
      %{id: :work_sup, start: {OddJob.Supervisor, :start_link, [[name: :work]]}, type: :supervisor}

  Normally you would start an `OddJob` pool under a supervision tree and not call
  `child_spec/1` directly.

      children = [{OddJob, :work}]
      Supervisor.start_link(children, strategy: :one_for_one)

  ## Arguments

  The `start_arg`, whether passed directly to `child_spec/1` or used as the second element of a child spec tuple,
  can be one of the following:

    * `name` - An atom which will be the name of the pool.

    * `opts` - A keyword list of options.

    * `{name, opts}` - A two element tuple where `name` is an atom and `opts` is a keyword list of
    options. If `opts` has a `:name` key it will be overridden by the first element of the tuple.

  See `start_link/1` for more information on start arguments and options, and the `Supervisor` module for more
  about child specs.
  """
  @doc since: "0.1.0"
  @spec child_spec(start_arg | {atom, [start_option]}) :: child_spec
  defdelegate child_spec(name), to: OddJob.Supervisor

  @doc """
  Starts an `OddJob` pool supervision tree linked to the current process.

  ## Arguments

  The `start_arg` can be one of the following:

    * `name` - An atom which will be the name of the pool. Use this option if you want your pool to assume
    the default config options.

    * `opts` - A keyword list of options. These options will override the default config. The available
    options are:

      * `:name` - an atom that will name the pool, and the only required key

      * `:pool_size` - an integer, the number of concurrent workers in the pool. Defaults to 5 or your application's
      config value.

      * `:max_restarts` - an integer, the number of worker restarts allowed in a given timeframe before all
      of the workers are restarted. Set a higher number if your jobs have a high rate of expected failure.
      Defaults to 5 or your application's config value.

      * `:max_seconds` - an integer, the timeframe in seconds in which `max_restarts` applies. Defaults to 3
      or your application's config value. See `Supervisor` for more info on restart intensity options.

  You can start an `OddJob` pool directly and dynamically:

      iex> {:ok, _pid} = OddJob.start_link(name: :event, pool_size: 10)
      iex> OddJob.async_perform(:event, fn -> :do_something end) |> OddJob.await()
      :do_something

  Normally you would instead start your pools inside a supervision tree:

      children = [{OddJob, name: :event, pool_size: 10}]
      Supervisor.start_link(children, strategy: :one_for_one)

  The second element of the child spec tuple can be any of the `start_arg`s accepted by `start_link/1` or
  `child_spec/1`. See `Supervisor` for more on starting supervision trees.
  """
  @doc since: "0.4.0"
  @spec start_link(start_arg) :: Supervisor.on_start()
  defdelegate start_link(arg), to: OddJob.Supervisor

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
  @doc since: "0.1.0"
  @spec perform(atom, function) :: :ok
  def perform(pool, fun) when is_atom(pool) and is_function(fun) do
    job = %Job{function: fun, owner: self()}

    pool
    |> pool_id()
    |> GenServer.cast({:perform, job})
  end

  @doc """
  Sends a collection of jobs to the pool.

  ## Examples

      iex> caller = self()
      iex> OddJob.perform_many(:job, 1..5, fn x -> send(caller, x) end)
      iex> for x <- 1..5 do
      ...>   receive do
      ...>     ^x -> x
      ...>   end
      ...> end
      [1, 2, 3, 4, 5]
  """
  @doc since: "0.4.0"
  @spec perform_many(atom, list | map, function) :: :ok
  def perform_many(pool, collection, fun)
      when is_atom(pool) and is_enumerable(collection) and is_function(fun, 1) do
    jobs = for item <- collection, do: %Job{function: fn -> fun.(item) end, owner: self()}

    pool
    |> pool_id()
    |> GenServer.cast({:perform_many, jobs})
  end

  @doc """
  Performs an async job that can be awaited on for the result.

  Functions like `Task.async/1` and `Task.await/2`.

  ## Examples

      iex> job = OddJob.async_perform(:job, fn -> :math.exp(100) end)
      iex> OddJob.await(job)
      2.6881171418161356e43
  """
  @doc since: "0.1.0"
  @spec async_perform(atom, function) :: job
  def async_perform(pool, fun) when is_atom(pool) and is_function(fun) do
    pool
    |> pool_id()
    |> Async.perform(fun)
  end

  @doc """
  Sends a collection of async jobs to the pool.

  There's a limit to the number of jobs that can be started with this function that
  roughly equals the BEAM's process limit.

  ## Examples

      iex> jobs = OddJob.async_perform_many(:job, 1..5, fn x -> x ** 2 end)
      iex> OddJob.await_many(jobs)
      [1, 4, 9, 16, 25]
  """
  @doc since: "0.4.0"
  @spec async_perform_many(atom, list | map, function) :: [job]
  def async_perform_many(pool, collection, fun)
      when is_atom(pool) and is_enumerable(collection) and is_function(fun, 1) do
    pool
    |> pool_id()
    |> Async.perform_many(collection, fun)
  end

  @doc """
  Awaits on an async job and returns the results.

  ## Examples

      iex> OddJob.async_perform(:job, fn -> :math.log(2.6881171418161356e43) end)
      ...> |> OddJob.await()
      100.0
  """
  @doc since: "0.1.0"
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
  @doc since: "0.2.0"
  @spec await_many([job], timeout) :: [any]
  def await_many(jobs, timeout \\ 5000) when is_list(jobs) do
    Async.await_many(jobs, timeout)
  end

  @doc """
  Sends a job to the `pool` after the given `timer` has elapsed.

  `timer` is an integer that indicates the number of milliseconds that should elapse before
  the job is sent to the pool. The timed message is executed under a separate supervised process,
  so if the caller crashes the job will still be performed. A timer reference is returned,
  which can be read with `Process.read_timer/1` or cancelled with `OddJob.cancel_timer/1`.

  ## Examples

      timer_ref = OddJob.perform_after(5000, :job, fn -> deferred_job() end)
      Process.read_timer(timer_ref)
      #=> 2836 # time remaining before job is sent to the pool
      OddJob.cancel_timer(timer_ref)
      #=> 1175 # job has been cancelled

      timer_ref = OddJob.perform_after(5000, :job, fn -> deferred_job() end)
      Process.sleep(6000)
      OddJob.cancel_timer(timer_ref)
      #=> false # too much time has passed to cancel the job
  """
  @doc since: "0.2.0"
  @spec perform_after(integer, atom, function) :: reference
  def perform_after(timer, pool, fun)
      when is_integer(timer) and is_atom(pool) and is_function(fun) do
    Scheduler.perform_after(timer, pool, fun)
  end

  @doc """
  Sends a job to the `pool` at the given `time`.

  `time` can be a `Time` or a `DateTime` struct. If a `Time` struct is received, then
  the job will be done the next time the clock strikes the given time. The timer is executed
  under a separate supervised process, so if the caller crashes the job will still be performed.
  A timer reference is returned, which can be read with `Process.read_timer/1` or canceled with
  `OddJob.cancel_timer/1`.

  ## Examples

      time = Time.utc_now() |> Time.add(600, :second)
      OddJob.perform_at(time, :job, fn -> scheduled_job() end)
  """
  @doc since: "0.2.0"
  @spec perform_at(Time.t() | DateTime.t(), atom, function) :: reference
  def perform_at(time, pool, fun)
      when (is_struct(time, Time) or is_struct(time, DateTime)) and
             is_atom(pool) and is_function(fun) do
    Scheduler.perform_at(time, pool, fun)
  end

  @doc """
  Cancels a scheduled job.

  `timer_ref` is the unique reference returned by `perform_at/3` or `perform_after/3`. This function
  returns the number of milliseconds left in the timer when cancelled, or `false` if the timer already
  expired. If the return is `false` you can assume that the job has already been sent to the pool
  for execution.

  NOTE: Cancelling the timer with this function ensures that the job is never executed *and* that
  the scheduler process is exited and not left "hanging". Using `Process.cancel_timer/1` will also
  cancel execution, but may leave hanging processes. A hanging scheduler process will eventually
  timeout, but not until one second after the expiration of the original timer.

  ## Examples

      iex> ref = OddJob.perform_after(500, :work, fn -> :never end)
      iex> time = OddJob.cancel_timer(ref)
      iex> is_integer(time)
      true

      iex> ref = OddJob.perform_after(10, :work, fn -> :never end)
      iex> Process.sleep(11)
      iex> OddJob.cancel_timer(ref)
      false
  """
  @doc since: "0.2.0"
  @spec cancel_timer(reference) :: non_neg_integer | false
  def cancel_timer(timer_ref) when is_reference(timer_ref) do
    Scheduler.cancel_timer(timer_ref)
  end

  @doc """
  Returns the pid and state of the job `pool`.

  ## Examples

      iex> {pid, %OddJob.Pool{id: id}} = OddJob.pool(:job)
      iex> is_pid(pid)
      true
      iex> id
      :job_pool
  """
  @doc since: "0.1.0"
  @spec pool(atom) :: {pid, pool}
  def pool(pool) when is_atom(pool) do
    state =
      pool
      |> pool_id()
      |> Pool.state()

    pid =
      pool
      |> pool_id()
      |> GenServer.whereis()

    {pid, state}
  end

  @doc """
  Returns the ID of the job `pool`.

  ## Examples

      iex> OddJob.pool_id(:job)
      :job_pool
  """
  @doc since: "0.1.0"
  @spec pool_id(atom) :: atom
  defdelegate pool_id(pool), to: OddJob.Supervisor

  @doc """
  Returns the pid of the job `pool`'s supervisor.

  There is no guarantee that the process will still be alive after the results are returned,
  as it could exit or be killed or restarted at any time. Use `supervisor_id/1` to obtain
  the persistent ID of the supervisor.

  ## Examples

      OddJob.supervisor(:job)
      #=> #PID<0.239.0>
  """
  @doc since: "0.1.0"
  @spec supervisor(atom) :: pid
  def supervisor(pool) when is_atom(pool) do
    pool
    |> supervisor_id()
    |> GenServer.whereis()
  end

  @doc """
  Returns the ID of the job `pool`'s worker supervisor.

  ## Examples

      iex> OddJob.supervisor_id(:job)
      :job_pool_worker_sup
  """
  @doc since: "0.1.0"
  @spec supervisor_id(atom) :: atom
  defdelegate supervisor_id(pool), to: OddJob.Pool.Supervisor, as: :id

  @doc """
  Returns a list of `pid`s for the specified worker pool.

  There is no guarantee that the processes will still be alive after the results are returned,
  as they could exit or be killed at any time.

  ## Examples

      OddJob.workers(:job)
      #=> [#PID<0.105.0>, #PID<0.106.0>, #PID<0.107.0>, #PID<0.108.0>, #PID<0.109.0>]
  """
  @doc since: "0.1.0"
  @spec workers(atom) :: [pid]
  def workers(pool) when is_atom(pool) do
    {_, %{workers: workers}} = pool(pool)
    workers
  end
end
