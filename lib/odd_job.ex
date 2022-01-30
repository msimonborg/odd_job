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

  @type job :: OddJob.Job.t()
  @type queue :: OddJob.Queue.t()
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
  @spec perform(atom, fun) :: :ok
  def perform(pool, fun) when is_atom(pool) and is_function(fun) do
    GenServer.call(queue_id(pool), {:perform, fun})
  end

  @doc """
  Performs an async job that can be awaited on for the result.

  Functions like `Task.async/1` and `Task.await/2`.

  # WIP

  ## Examples

      iex> job = OddJob.perform_async(:work, fn -> :math.exp(100) end)
      iex> OddJob.await(job)
      2.6881171418161356e43
  """
  @spec perform_async(atom, fun) :: job
  def perform_async(pool, fun) when is_atom(pool) and is_function(fun) do
    GenServer.call(queue_id(pool), {:perform_async, fun})
  end

  @doc """
  Awaits on an async job and returns the results.

  # WIP

  ## Examples

      iex> OddJob.perform_async(:work, fn -> :math.log(2.6881171418161356e43) end)
      ...> |> OddJob.await()
      100.0
  """
  @spec await(job) :: any
  def await(_job) do
    receive do
      %OddJob.Job{results: results} -> results
    end
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
    state = queue_id |> OddJob.Queue.state()
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
