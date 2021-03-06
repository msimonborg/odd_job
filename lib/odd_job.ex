defmodule OddJob do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)
             |> String.replace("#usage", "#module-usage")
             |> String.replace("#supervising-job-pools", "#module-supervising-job-pools")

  @moduledoc since: "0.1.0"

  import OddJob.Guards

  alias OddJob.{Async, Job, Queue, Registry, Scheduler}

  @type child_spec :: OddJob.Pool.child_spec()
  @type date_time :: DateTime.t()
  @type invalid_datetime :: {:error, :invalid_datetime}
  @type job :: Job.t()
  @type name :: Registry.name()
  @type not_found :: {:error, :not_found}
  @type options :: OddJob.Pool.options()
  @type pool :: atom
  @type queue :: Queue.t()
  @type start_option :: OddJob.Pool.start_option()
  @type timer :: non_neg_integer

  @doc """
  A macro for creating jobs with an expressive DSL.

  `perform_this/2` works like `perform/2` except it accepts a `do` block instead of an anonymous function.

  ## Examples

  You must `import` or `require` `OddJob` to use macros:

      import OddJob
      alias MyApp.Job

      perform_this Job do
        some_work()
        some_other_work()
      end

      perform_this Job, do: something_hard()
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
      alias MyApp.Job

      time = ~T[03:00:00.000000]
      perform_this Job, at: time do
        scheduled_work()
      end

      perform_this Job, after: 5000, do: something_important()

      perform_this Job, :async do
        get_data()
      end
      |> await()

      iex> (perform_this OddJob.Pool, :async, do: 10 ** 2) |> await()
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

      iex> children = [OddJob.child_spec(name: MyApp.Media)]
      [%{id: MyApp.Media, start: {OddJob.Pool, :start_link, [[name: MyApp.Media]]}, type: :supervisor}]
      iex> {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)
      iex> (MyApp.Media |> OddJob.workers() |> length()) == System.schedulers_online()
      true

  Normally you would start an `OddJob` pool under a supervision tree with a child specification tuple
  and not call `child_spec/1` directly.

      children = [{OddJob, name: MyApp.Media}]
      Supervisor.start_link(children, strategy: :one_for_one)

  You must pass a keyword list of options to `child_spec/1`, or as the second element of the
  child specification tuple.

  ## Options

    * `:name` - An `atom` that names the pool. This argument is required.

    * `:pool_size` - A positive `integer`, the number of concurrent workers in the pool. Defaults to 5 or your application's
    config value.

    * `:max_restarts` - A positive `integer`, the number of worker restarts allowed in a given timeframe before all
    of the workers are restarted. Set a higher number if your jobs have a high rate of expected failure.
    Defaults to 5 or your application's config value.

    * `:max_seconds` - A positive `integer`, the timeframe in seconds in which `max_restarts` applies. Defaults to 3
    or your application's config value. See `Supervisor` for more info on restart intensity options.

  See the `Supervisor` module for more about child specs.
  """
  @doc since: "0.1.0"
  @spec child_spec(options) :: child_spec
  def child_spec(opts) when is_list(opts) do
    opts
    |> validate_name!()
    |> OddJob.Pool.child_spec()
  end

  @doc """
  Starts an `OddJob.Pool` supervision tree linked to the current process.

  You can start an `OddJob` pool dynamically with `start_link/1` to start processing concurrent jobs:

      iex> {:ok, _pid} = OddJob.start_link(name: MyApp.Event, pool_size: 10)
      iex> OddJob.async_perform(MyApp.Event, fn -> :do_something end) |> OddJob.await()
      :do_something

  In most cases you would instead start your pools inside a supervision tree:

      children = [{OddJob, name: MyApp.Event, pool_size: 10}]
      Supervisor.start_link(children, strategy: :one_for_one)

  See `OddJob.child_spec/1` for a list of available options.

  See `Supervisor` for more on child specifications and supervision trees.
  """
  @doc since: "0.4.0"
  @spec start_link(options) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    opts
    |> validate_name!()
    |> OddJob.Pool.start_link()
  end

  defp validate_name!(opts) do
    name = Keyword.fetch!(opts, :name)

    unless is_atom(name) do
      raise ArgumentError,
        message: """
        Expected `name` to be an atom. Got #{inspect(name)}
        """
    end

    opts
  end

  @doc """
  Performs a fire and forget job.

  Casts the `function` to the job `pool`, and if a worker is available it is performed
  immediately. If no workers are available the job is added to the back of a FIFO queue to be
  performed as soon as a worker is available.

  Returns `:ok` if the pool process exists at the time of calling, or `{:error, :not_found}`
  if it doesn't. The job is casted to the pool, so there can be no guarantee that the pool process
  will still exist if it crashes between the beginning of the function call and when the message
  is received.

  Use this function for interaction with other processes or the outside world where you don't
  care about the return results or whether it succeeds.

  ## Examples

      iex> parent = self()
      iex> :ok = perform(OddJob.Pool, fn -> send(parent, :hello) end)
      iex> receive do
      ...>   msg -> msg
      ...> end
      :hello

      iex> perform(:does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.1.0"
  @spec perform(pool, function) :: :ok | not_found
  def perform(pool, function) when is_atom(pool) and is_function(function, 0) do
    with {:ok, queue} <- queue_name(pool), do: Queue.perform(queue, function)
  end

  @doc """
  Sends a collection of jobs to the pool.

  Enumerates over the collection, using each member as the argument to an anonymous function
  witn an arity of `1`. The collection of jobs is sent in bulk to the pool where they will be
  immediately performed by any available workers. If there are no available workers the jobs
  are added to the FIFO queue. Jobs are guaranteed to always process in the same order of the
  original collection, and insertion into the queue is atomic. No jobs sent from other processes
  can be inserted between any member of the collection.

  Returns `:ok` if the pool process exists at the time of calling, or `{:error, :not_found}`
  if it doesn't. See `perform/2` for more.

  ## Examples

      iex> caller = self()
      iex> perform_many(OddJob.Pool, 1..5, & send(caller, &1))
      iex> for x <- 1..5 do
      ...>   receive do
      ...>     ^x -> x
      ...>   end
      ...> end
      [1, 2, 3, 4, 5]

      iex> perform_many(:does_not_exist, ["never", "called"], &(&1))
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec perform_many(pool, list | map, function) :: :ok | not_found
  def perform_many(pool, collection, function)
      when is_atom(pool) and is_enumerable(collection) and is_function(function, 1) do
    with {:ok, queue} <- queue_name(pool) do
      Queue.perform_many(queue, collection, function)
    end
  end

  @doc """
  Performs an async job that can be awaited on for the result.

  Returns the `OddJob.Job.t()` struct if the pool server exists at the time of calling, or
  {:error, :not_found} if it doesn't.

  Functions similarly to `Task.async/1` and `Task.await/2` with some tweaks. Since the workers in the
  `pool` already exist when this function is called and may be busy performing other jobs, it is
  unknown at the time of calling when the job will be performed and by which worker process.

  An `OddJob.Async.Proxy` is dynamically created and linked and monitored by the caller. The `Proxy`
  handles the transactions with the pool and is notified when a worker is assigned. The proxy
  links and monitors the worker immediately before performance of the job, forwarding any exits or
  crashes to the caller. The worker returns the results to the proxy, which then passes them to the
  caller with a `{ref, result}` message. The proxy immediately exits with reason `:normal` after the
  results are sent back to the caller.

  See `await/2` and `await_many/2` for functions to retrieve the results, and the `Task` module for
  more information on the `async/await` patter and when you may want to use it.

  ## Examples

      iex> job = async_perform(OddJob.Pool, fn -> :math.exp(100) end)
      iex> await(job)
      2.6881171418161356e43

      iex> async_perform(:does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.1.0"
  @spec async_perform(pool, function) :: job | not_found
  def async_perform(pool, function) when is_atom(pool) and is_function(function, 0) do
    with {:ok, queue} <- queue_name(pool), do: Async.perform(pool, queue, function)
  end

  @doc """
  Sends a collection of async jobs to the pool.

  Returns a list of `OddJob.Job.t()` structs if the pool server exists at the time of
  calling, or {:error, :not_found} if it doesn't.

  Enumerates over the collection, using each member as the argument to an anonymous function
  with an arity of `1`. See `async_perform/2` and `perform/2` for more information.

  There's a limit to the number of jobs that can be started with this function that
  roughly equals the BEAM's process limit.

  ## Examples

      iex> jobs = async_perform_many(OddJob.Pool, 1..5, &(&1 ** 2))
      iex> await_many(jobs)
      [1, 4, 9, 16, 25]

      iex> async_perform_many(:does_not_exist, ["never", "called"], &(&1))
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec async_perform_many(pool, list | map, function) :: [job] | not_found
  def async_perform_many(pool, collection, function)
      when is_atom(pool) and is_enumerable(collection) and is_function(function, 1) do
    with {:ok, queue} <- queue_name(pool) do
      Async.perform_many(pool, queue, collection, function)
    end
  end

  @doc """
  Awaits on an async job reply and returns the results.

  The current process and the worker process are linked during execution of the job by an
  `OddJob.Async.Proxy`. In case the worker process dies during execution, the current process
  will exit with the same reason as the worker.

  A timeout, in milliseconds or :infinity, can be given with a default value of 5000. If the
  timeout is exceeded, then the current process will exit. If the worker process is linked to the
  current process which is the case when a job is started with async, then the worker process will
  also exit.

  This function assumes the proxy's monitor is still active or the monitor's :DOWN message is in the
  message queue. If it has been demonitored, or the message already received, this function will wait
  for the duration of the timeout awaiting the message.

  ## Examples

      iex> async_perform(OddJob.Pool, fn -> :math.log(2.6881171418161356e43) end)
      ...> |> await()
      100.0
  """
  @doc since: "0.1.0"
  @spec await(job, timeout) :: term
  def await(job, timeout \\ 5000) when is_struct(job, Job),
    do: Async.await(job, timeout)

  @doc """
  Awaits replies from multiple async jobs and returns them in a list.

  This function receives a list of jobs and waits for their replies in the given time interval.
  It returns a list of the results, in the same order as the jobs supplied in the `jobs` input argument.

  The current process and each worker process are linked during execution of the job by an
  `OddJob.Async.Proxy`. If any of the worker processes dies, the caller process will exit with the same
  reason as that worker.

  A timeout, in milliseconds or `:infinity`, can be given with a default value of `5000`. If the timeout
  is exceeded, then the caller process will exit. Any worker processes that are linked to the caller process
  (which is the case when a job is started with `async_perform/2`) will also exit.

  This function assumes the proxies' monitors are still active or the monitor's :DOWN message is in the
  message queue. If any jobs have been demonitored, or the message already received, this function will
  wait for the duration of the timeout.

  ## Examples

      iex> job1 = async_perform(OddJob.Pool, fn -> 2 ** 2 end)
      iex> job2 = async_perform(OddJob.Pool, fn -> 3 ** 2 end)
      iex> [job1, job2] |> await_many()
      [4, 9]
  """
  @doc since: "0.2.0"
  @spec await_many([job], timeout) :: [term]
  def await_many(jobs, timeout \\ 5000) when is_list(jobs),
    do: Async.await_many(jobs, timeout)

  @doc """
  Sends a job to the `pool` after the given `timer` has elapsed.

  `timer` is an integer that indicates the number of milliseconds that should elapse before
  the job is sent to the pool. The timed message is executed under a separate supervised process,
  so if the current process crashes the job will still be performed. A timer reference is returned,
  which can be read with `Process.read_timer/1` or cancelled with `OddJob.cancel_timer/1`. Returns
  `{:error, :not_found}` if the `pool` server does not exist at the time this function is
  called.

  ## Examples

      timer_ref = perform_after(5000, OddJob.Pool, &deferred_job/0)
      Process.read_timer(timer_ref)
      #=> 2836 # time remaining before job is sent to the pool
      cancel_timer(timer_ref)
      #=> 1175 # job has been cancelled

      timer_ref = perform_after(5000, OddJob.Pool, &deferred_job/0)
      Process.sleep(6000)
      cancel_timer(timer_ref)
      #=> false # too much time has passed to cancel the job

      iex> perform_after(5000, :does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.2.0"
  @spec perform_after(timer, pool, function) :: reference | not_found
  def perform_after(timer, pool, fun)
      when is_atom(pool) and is_timer(timer) and is_function(fun, 0) do
    with {:ok, _} <- queue_name(pool), do: Scheduler.perform(timer, pool, fun)
  end

  @doc """
  Sends a collection of jobs to the `pool` after the given `timer` has elapsed.

  Enumerates over the collection, using each member as the argument to an anonymous function
  with an arity of `1`. Returns a single timer `reference`. The `timer` is watched by a single
  process that will send the entire batch of jobs to the pool when the timer expires. See
  `perform_after/3` for more information about arguments and timers.

  Consider using this function instead of `perform_after/3` when scheduling a large batch of jobs.
  `perform_after/3` starts a separate scheduler process per job, whereas this function starts a
  single scheduler process for the whole batch.

  Returns `{:error, :not_found}` if the `pool` does not exist at the time the function
  is called.

  ## Examples

      timer_ref = perform_many_after(5000, OddJob.Pool, 1..5, &(&1 ** 2))
      #=> #Reference<0.1431903625.286261254.39156>
      # fewer than 5 seconds pass
      cancel_timer(timer_ref)
      #=> 2554 # returns the time remaining. All jobs in the collection have been canceled

      timer_ref = perform_many_after(5000, OddJob.Pool, 1..5, &(&1 ** 2))
      #=> #Reference<0.1431903625.286261254.39178>
      # more than 5 seconds pass
      cancel_timer(timer_ref)
      #=> false # too much time has passed, all jobs have been queued

      iex> perform_many_after(5000, :does_not_exist, ["never", "called"], &(&1))
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec perform_many_after(timer, pool, list | map, function) :: reference | not_found
  def perform_many_after(timer, pool, collection, function)
      when is_atom(pool) and is_timer(timer) and is_enumerable(collection) and
             is_function(function, 1) do
    with {:ok, _} <- queue_name(pool) do
      Scheduler.perform_many(timer, pool, collection, function)
    end
  end

  @doc """
  Sends a job to the `pool` at the given `time`.

  `time` must be a `DateTime` struct for a time in the future. The timer is executed
  under a separate supervised process, so if the caller crashes the job will still be performed.
  A timer reference is returned, which can be read with `Process.read_timer/1` or canceled with
  `OddJob.cancel_timer/1`. Returns `{:error, :not_found}` if the `pool` server does not exist at
  the time this function is called, or `{:error, :invalid_datetime}` if the DateTime given
  is already past.

  ## Examples

      time = DateTime.utc_now() |> DateTime.add(600, :second)
      perform_at(time, OddJob.Pool, &schedule_job/0)

      iex> time = DateTime.utc_now() |> DateTime.add(600, :second)
      iex> perform_at(time, :does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.2.0"
  @spec perform_at(date_time, pool, function) :: reference | not_found | invalid_datetime
  def perform_at(date_time, pool, fun)
      when is_atom(pool) and is_struct(date_time, DateTime) and is_function(fun, 0) do
    with {:ok, _} <- queue_name(pool),
         {:ok, timer} <- validate_date_time(date_time) do
      Scheduler.perform(timer, pool, fun)
    end
  end

  @doc """
  Sends a collection of jobs to the `pool` at the given `time`.

  Enumerates over the collection, using each member as the argument to an anonymous function
  with an arity of `1`. Returns a single timer `reference`. The timer is watched by a single
  process that will send the entire batch of jobs to the pool when the timer expires. See
  `perform_at/3` for more information about arguments and timers.

  Consider using this function instead of `perform_at/3` when scheduling a large batch of jobs.
  `perform_at/3` starts a separate scheduler process per job, whereas this function starts a
  single scheduler process for the whole batch.

  Returns `{:error, :not_found}` if the `pool` does not exist at the time the function
  is called, or `{:error, :invalid_datetime}` if the DateTime given
  is already past.

  ## Examples

      time = DateTime.utc_now() |> DateTime.add(5, :second)
      timer_ref = perform_many_at(time, OddJob.Pool, 1..5, &(&1 ** 2))
      #=> #Reference<0.1431903625.286261254.39156>
      # fewer than 5 seconds pass
      cancel_timer(timer_ref)
      #=> 2554 # returns the time remaining. All jobs in the collection have been canceled

      time = DateTime.utc_now() |> DateTime.add(5, :second)
      timer_ref = perform_many_at(time, OddJob.Pool, 1..5, &(&1 ** 2))
      #=> #Reference<0.1431903625.286261254.39178>
      # more than 5 seconds pass
      cancel_timer(timer_ref)
      #=> false # too much time has passed, all jobs have been queued

      iex> time = DateTime.utc_now() |> DateTime.add(5, :second)
      iex> perform_many_at(time, :does_not_exist, ["never", "called"], &(&1))
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec perform_many_at(date_time, pool, list | map, function) ::
          reference | not_found | invalid_datetime
  def perform_many_at(date_time, pool, collection, function)
      when is_struct(date_time, DateTime) and is_atom(pool) and is_enumerable(collection) and
             is_function(function, 1) do
    with {:ok, _} <- queue_name(pool),
         {:ok, timer} <- validate_date_time(date_time) do
      Scheduler.perform_many(timer, pool, collection, function)
    end
  end

  defp validate_date_time(date_time) do
    case DateTime.diff(date_time, DateTime.utc_now(), :millisecond) do
      diff when diff >= 0 -> {:ok, diff}
      _ -> {:error, :invalid_datetime}
    end
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

      iex> ref = perform_after(500, OddJob.Pool, fn -> :never end)
      iex> time = cancel_timer(ref)
      iex> is_integer(time)
      true

      iex> ref = perform_after(10, OddJob.Pool, fn -> :never end)
      iex> Process.sleep(11)
      iex> cancel_timer(ref)
      false
  """
  @doc since: "0.2.0"
  @spec cancel_timer(reference) :: non_neg_integer | false
  def cancel_timer(timer_ref) when is_reference(timer_ref),
    do: Scheduler.cancel_timer(timer_ref)

  @doc """
  Returns a two element tuple `{pid, state}` with the `pid` of the job `queue` as the first element.
  The second element is the `state` of the queue represented by an `OddJob.Queue` struct.

  The queue `state` has the following fields:

    * `:workers` - A list of the `pid`s of all workers in the pool

    * `:assigned` - The `pid`s of the workers currently assigned to jobs

    * `:jobs` - A list of `OddJob.Job` structs in the queue awaiting execution

    * `:pool` - The Elixir term naming the `pool` that the queue belongs to

  Returns `{:error, :not_found}` if the `queue` server does not exist at
  the time this function is called.

  ## Examples

      iex> {pid, %OddJob.Queue{pool: pool}} = queue(OddJob.Pool)
      iex> is_pid(pid)
      true
      iex> pool
      OddJob.Pool

      iex> queue(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.1.0"
  @spec queue(pool) :: {pid, queue} | not_found
  def queue(pool) when is_atom(pool) do
    name = OddJob.Utils.queue_name(pool)

    case GenServer.whereis(name) do
      nil ->
        {:error, :not_found}

      pid ->
        state = Queue.state(name)
        {pid, state}
    end
  end

  @doc """
  Returns the registered name for the `queue` process.

  The successful return value is `{:ok, name}`, where name is the registered
  name in `:via`. See the `Registry` module for more information on `:via`
  process name registration.

  Returns `{:error, :not_found}` if the `queue` server does not exist at
  the time this function is called.

  ## Examples

      iex> with {:ok, name} <- queue_name(OddJob.Pool), do: name
      {:via, Registry, {OddJob.Registry, {OddJob.Pool, :queue}}}

      iex> queue_name(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec queue_name(pool) :: {:ok, name} | not_found
  def queue_name(pool) when is_atom(pool) do
    name = OddJob.Utils.queue_name(pool)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _ -> {:ok, name}
    end
  end

  @doc """
  Returns the pid of the `OddJob.Pool.Supervisor` that supervises the job `pool`'s workers.

  Returns `{:error, :not_found}` if the process does not exist at
  the time this function is called.

  There is no guarantee that the process identified by the `pid` will still be alive
  after the results are returned, as it could exit or be killed or restarted at any time.
  Use `pool_supervisor_name/1` to obtain the persistent registered name of the supervisor.

  ## Examples

      iex> is_pid pool_supervisor(OddJob.Pool)
      true

      iex> pool_supervisor(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec pool_supervisor(pool) :: pid | not_found
  def pool_supervisor(pool) when is_atom(pool) do
    case pool |> OddJob.Utils.pool_supervisor_name() |> GenServer.whereis() do
      nil -> {:error, :not_found}
      pid -> pid
    end
  end

  @doc """
  Returns the registered name of the `OddJob.Pool.Supervisor` process for the given `pool`.

  The `OddJob.Pool.Supervisor` supervises the `pool`'s workers.The successful return value
  is `{:ok, name}`, where name is the registered name in `:via`. See the `Registry` module
  for more information on `:via` process name registration.

  Returns `{:error, :not_found}` if the process does not exist at
  the time this function is called.

  ## Examples

      iex> with {:ok, name} <- pool_supervisor_name(OddJob.Pool), do: name
      {:via, Registry, {OddJob.Registry, {OddJob.Pool, :pool_sup}}}

      iex> pool_supervisor_name(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec pool_supervisor_name(pool) :: {:ok, name} | not_found
  def pool_supervisor_name(pool) when is_atom(pool) do
    name = OddJob.Utils.pool_supervisor_name(pool)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _ -> {:ok, name}
    end
  end

  @doc """
  Returns a list of `pid`s for the specified worker pool.

  There is no guarantee that the processes will still be alive after the
  results are returned, as they could exit or be killed at any time.

  Returns `{:error, :not_found}` if the `pool` does not exist at
  the time this function is called.

  ## Examples

      iex> workers = workers(OddJob.Pool)
      iex> Enum.all?(workers, &is_pid/1)
      true

      iex> workers(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.1.0"
  @spec workers(pool) :: [pid] | not_found
  def workers(pool) do
    case pool |> OddJob.Utils.pool_supervisor_name() |> GenServer.whereis() do
      nil ->
        {:error, :not_found}

      sup ->
        for {_id, pid, :worker, [OddJob.Pool.Worker]} <- Supervisor.which_children(sup), do: pid
    end
  end

  @doc """
  Returns the `pid` of the top level supervisor in the `pool` supervision tree, `nil`
  if a process can't be found.

  ## Example

      iex> {:ok, pid} = OddJob.start_link(name: :whereis)
      iex> OddJob.whereis(:whereis) == pid
      true

      iex> OddJob.whereis(:where_it_is_not) == nil
      true
  """
  @doc since: "0.4.0"
  @spec whereis(pool) :: pid | nil
  def whereis(pool) do
    GenServer.whereis(pool)
  end
end
