defmodule OddJob do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)
             |> String.replace("#usage", "#module-usage")
             |> String.replace("#supervising-job-pools", "#module-supervising-job-pools")

  @moduledoc since: "0.1.0"

  alias OddJob.{Async, Job, Queue, Registry, Scheduler}

  @type pool :: atom
  @type not_found :: {:error, :not_found}
  @type job :: Job.t()
  @type queue :: Queue.t()
  @type name :: Registry.name()
  @type start_arg :: OddJob.Supervisor.start_arg()
  @type start_option :: OddJob.Supervisor.start_option()
  @type child_spec :: OddJob.Supervisor.child_spec()

  @doc false
  @doc since: "0.4.0"
  defguard is_enumerable(term) when is_list(term) or is_map(term)

  @doc false
  @doc since: "0.4.0"
  defguard is_time(time) when is_struct(time, DateTime)

  @doc false
  @doc since: "0.4.0"
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Returns a specification to start this module under a supervisor.
        See `Supervisor`.
        """
      end

      def child_spec(arg) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]},
          type: :supervisor
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Starts an OddJob supervision tree linked to the current process.
        See `OddJob.start_link/2`.
        """
      end

      def start_link([]), do: OddJob.start_link(__MODULE__)

      def start_link(arg) do
        IO.warn("""
        Your initial argument was ignored because you have not defined a custom
        `start_link/1` in #{__MODULE__}.
        """)

        start_link([])
      end

      defoverridable child_spec: 1, start_link: 1
    end
  end

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

      iex> (perform_this MyApp.Job, :async, do: 10 ** 2) |> await()
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

      iex> children = [OddJob.child_spec(MyApp.Media)]
      [%{id: {OddJob, MyApp.Media}, start: {OddJob.Supervisor, :start_link, [MyApp.Media, []]}, type: :supervisor}]
      iex> {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)
      iex> OddJob.workers(MyApp.Media) |> length()
      5

  Normally you would start an `OddJob` pool under a supervision tree with a child specification tuple
  and not call `child_spec/1` directly.

      children = [{OddJob, MyApp.Media}]
      Supervisor.start_link(children, strategy: :one_for_one)

  ## Arguments

  The `start_arg`, whether passed directly to `child_spec/1` or used as the second element of a child spec tuple,
  can be one of the following:

    * A `name` must be an atom and will be the name of the pool. Use this if you want to start a pool
    with the default config options.

    * A keyword list of options. `:name` is a required key and will name the pool. The other available
    options will override the default config and are detailed in `start_link/2`.

  See the `Supervisor` module for more about child specs.
  """
  @doc since: "0.1.0"
  @spec child_spec(start_arg) :: child_spec
  defdelegate child_spec(start_arg), to: OddJob.Supervisor

  @doc """
  Starts an `OddJob` pool supervision tree linked to the current process.

  ## Arguments

    * `name` - An atom that names the pool. This argument is required.

    * `opts` - A keyword list of options. These options will override the default config. The available
    options are:

      * `pool_size: integer` - the number of concurrent workers in the pool. Defaults to 5 or your application's
      config value.

      * `max_restarts: integer` - the number of worker restarts allowed in a given timeframe before all
      of the workers are restarted. Set a higher number if your jobs have a high rate of expected failure.
      Defaults to 5 or your application's config value.

      * `max_seconds: integer` - the timeframe in seconds in which `max_restarts` applies. Defaults to 3
      or your application's config value. See `Supervisor` for more info on restart intensity options.

  You can start an `OddJob` pool dynamically with `start_link/2` to start processing concurrent jobs:

      iex> {:ok, _pid} = OddJob.start_link(MyApp.Event, pool_size: 10)
      iex> OddJob.async_perform(MyApp.Event, fn -> :do_something end) |> OddJob.await()
      :do_something

  In most cases you would instead start your pools inside a supervision tree:

      children = [{OddJob, name: MyApp.Event, pool_size: 10}]
      Supervisor.start_link(children, strategy: :one_for_one)

  The second element of the child spec tuple must be one of the `start_arg`s accepted by `child_spec/1`.
  See `Supervisor` for more on starting supervision trees.
  """
  @doc since: "0.4.0"
  @spec start_link(pool, [start_option]) :: Supervisor.on_start()
  defdelegate start_link(name, opts \\ []), to: OddJob.Supervisor

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
      iex> :ok = OddJob.perform(OddJob.Job, fn -> send(parent, :hello) end)
      iex> receive do
      ...>   msg -> msg
      ...> end
      :hello

      iex> OddJob.perform(:does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.1.0"
  @spec perform(pool, function) :: :ok | not_found
  def perform(pool, function) when is_atom(pool) and is_function(function, 0) do
    case pool |> queue_name() do
      {:error, :not_found} ->
        {:error, :not_found}

      server ->
        job = %Job{function: function, owner: self()}
        GenServer.cast(server, {:perform, job})
    end
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
      iex> OddJob.perform_many(OddJob.Job, 1..5, fn x -> send(caller, x) end)
      iex> for x <- 1..5 do
      ...>   receive do
      ...>     ^x -> x
      ...>   end
      ...> end
      [1, 2, 3, 4, 5]

      iex> OddJob.perform_many(:does_not_exist, ["never", "called"], fn x -> x end)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec perform_many(pool, list | map, function) :: :ok | not_found
  def perform_many(pool, collection, function)
      when is_atom(pool) and is_enumerable(collection) and is_function(function, 1) do
    case pool |> queue_name() do
      {:error, :not_found} ->
        {:error, :not_found}

      server ->
        jobs =
          for member <- collection do
            %Job{function: fn -> function.(member) end, owner: self()}
          end

        GenServer.cast(server, {:perform_many, jobs})
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

      iex> job = OddJob.async_perform(OddJob.Job, fn -> :math.exp(100) end)
      iex> OddJob.await(job)
      2.6881171418161356e43

      iex> OddJob.async_perform(:does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.1.0"
  @spec async_perform(pool, function) :: job | not_found
  def async_perform(pool, function) when is_atom(pool) and is_function(function, 0) do
    case pool |> queue_name() do
      {:error, :not_found} -> {:error, :not_found}
      _ -> Async.perform(pool, function)
    end
  end

  @doc """
  Sends a collection of async jobs to the pool.

  Returns a list of `OddJob.Job.t()` structs if the pool server exists at the time of
  calling, or {:error, :not_found} if it doesn't.

  Enumerates over the collection, using each member as the argument to an anonymous function
  witn an arity of `1`. See `async_perform/2` and `perform/2` for more information.

  There's a limit to the number of jobs that can be started with this function that
  roughly equals the BEAM's process limit.

  ## Examples

      iex> jobs = OddJob.async_perform_many(OddJob.Job, 1..5, fn x -> x ** 2 end)
      iex> OddJob.await_many(jobs)
      [1, 4, 9, 16, 25]

      iex> OddJob.async_perform_many(:does_not_exist, ["never", "called"], fn x -> x end)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec async_perform_many(pool, list | map, function) :: [job] | not_found
  def async_perform_many(pool, collection, function)
      when is_atom(pool) and is_enumerable(collection) and is_function(function, 1) do
    case pool |> queue_name() do
      {:error, :not_found} -> {:error, :not_found}
      _ -> Async.perform_many(pool, collection, function)
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

      iex> OddJob.async_perform(OddJob.Job, fn -> :math.log(2.6881171418161356e43) end)
      ...> |> OddJob.await()
      100.0
  """
  @doc since: "0.1.0"
  @spec await(job, timeout) :: term
  def await(job, timeout \\ 5000) when is_struct(job, Job) do
    Async.await(job, timeout)
  end

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

      iex> job1 = OddJob.async_perform(OddJob.Job, fn -> 2 ** 2 end)
      iex> job2 = OddJob.async_perform(OddJob.Job, fn -> 3 ** 2 end)
      iex> [job1, job2] |> OddJob.await_many()
      [4, 9]
  """
  @doc since: "0.2.0"
  @spec await_many([job], timeout) :: [term]
  def await_many(jobs, timeout \\ 5000) when is_list(jobs) do
    Async.await_many(jobs, timeout)
  end

  @doc """
  Sends a job to the `pool` after the given `timer` has elapsed.

  `timer` is an integer that indicates the number of milliseconds that should elapse before
  the job is sent to the pool. The timed message is executed under a separate supervised process,
  so if the current process crashes the job will still be performed. A timer reference is returned,
  which can be read with `Process.read_timer/1` or cancelled with `OddJob.cancel_timer/1`. Returns
  `{:error, :not_found}` if the `pool` server does not exist at the time this function is
  called.

  ## Examples

      timer_ref = OddJob.perform_after(5000, OddJob.Job, fn -> deferred_job() end)
      Process.read_timer(timer_ref)
      #=> 2836 # time remaining before job is sent to the pool
      OddJob.cancel_timer(timer_ref)
      #=> 1175 # job has been cancelled

      timer_ref = OddJob.perform_after(5000, OddJob.Job, fn -> deferred_job() end)
      Process.sleep(6000)
      OddJob.cancel_timer(timer_ref)
      #=> false # too much time has passed to cancel the job

      iex> OddJob.perform_after(5000, :does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.2.0"
  @spec perform_after(integer, pool, function) :: reference | not_found
  def perform_after(timer, pool, fun)
      when is_atom(pool) and is_integer(timer) and is_function(fun, 0) do
    case pool |> queue_name() do
      {:error, :not_found} -> {:error, :not_found}
      _ -> Scheduler.perform_after(timer, pool, fun)
    end
  end

  @doc """
  Sends a job to the `pool` at the given `time`.

  `time` must be a `DateTime` struct for a time in the future. The timer is executed
  under a separate supervised process, so if the caller crashes the job will still be performed.
  A timer reference is returned, which can be read with `Process.read_timer/1` or canceled with
  `OddJob.cancel_timer/1`. Returns `{:error, :not_found}` if the `pool` server does not exist at
  the time this function is called.

  ## Examples

      time = DateTime.utc_now() |> DateTime.add(600, :second)
      OddJob.perform_at(time, OddJob.Job, fn -> scheduled_job() end)

      iex> time = DateTime.utc_now() |> DateTime.add(600, :second)
      iex> OddJob.perform_at(time, :does_not_exist, fn -> "never called" end)
      {:error, :not_found}
  """
  @doc since: "0.2.0"
  @spec perform_at(DateTime.t(), pool, function) :: reference | not_found
  def perform_at(time, pool, fun)
      when is_atom(pool) and is_time(time) and is_function(fun) do
    case pool |> queue_name() do
      {:error, :not_found} -> {:error, :not_found}
      _ -> Scheduler.perform_at(time, pool, fun)
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

      iex> {pid, %OddJob.Queue{pool: pool}} = OddJob.queue(OddJob.Job)
      iex> is_pid(pid)
      true
      iex> pool
      OddJob.Job

      iex> OddJob.queue(:does_not_exist)
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
        state = Queue.state(pool)
        {pid, state}
    end
  end

  @doc """
  Returns the registered name in `:via` for the `queue` process. See the
  `Registry` module for more information on `:via` process name registration.

  Returns `{:error, :not_found}` if the `queue` server does not exist at
  the time this function is called.

  ## Examples

      iex> OddJob.queue_name(OddJob.Job)
      {:via, Registry, {OddJob.Registry, {OddJob.Job, :queue}}}

      iex> OddJob.queue_name(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec queue_name(pool) :: name | not_found
  def queue_name(pool) when is_atom(pool) do
    name = OddJob.Utils.queue_name(pool)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _ -> name
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

      OddJob.pool_supervisor(OddJob.Job)
      #=> #PID<0.239.0>

      iex> OddJob.pool_supervisor(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec pool_supervisor(pool) :: pid | not_found
  def pool_supervisor(pool) when is_atom(pool) do
    case pool |> pool_supervisor_name() |> GenServer.whereis() do
      nil -> {:error, :not_found}
      pid -> pid
    end
  end

  @doc """
  Returns the registered name in `:via` of the `OddJob.Pool.Supervisor` that
  supervises the `pool`'s workers

  Returns `{:error, :not_found}` if the process does not exist at
  the time this function is called.

  ## Examples

      iex> OddJob.pool_supervisor_name(OddJob.Job)
      {:via, Registry, {OddJob.Registry, {OddJob.Job, :pool_sup}}}

      iex> OddJob.pool_supervisor_name(:does_not_exist)
      {:error, :not_found}
  """
  @doc since: "0.4.0"
  @spec pool_supervisor_name(pool) :: name | not_found
  def pool_supervisor_name(pool) when is_atom(pool) do
    name = OddJob.Utils.pool_supervisor_name(pool)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _ -> name
    end
  end

  @doc """
  Returns a list of `pid`s for the specified worker pool.

  There is no guarantee that the processes will still be alive after the
  results are returned, as they could exit or be killed at any time.

  Returns `{:error, :not_found}` if the `pool` does not exist at
  the time this function is called.

  ## Examples

      OddJob.workers(OddJob.Job)
      #=> [#PID<0.105.0>, #PID<0.106.0>, #PID<0.107.0>, #PID<0.108.0>, #PID<0.109.0>]

      iex> OddJob.workers(:does_not_exist)
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

      iex> {:ok, pid} = OddJob.start_link(:whereis)
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
