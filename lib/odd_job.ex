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

  @type queue :: OddJob.Queue.t()
  @type child_spec :: %{
          id: atom,
          start: {OddJob.Supervisor, :start_link, [atom]},
          type: :supervisor
        }

  @spec child_spec(atom) :: child_spec
  defdelegate child_spec(name), to: OddJob.Supervisor

  @doc """
  Performs a fire and forget job.

  ## Examples

      iex> parent = self()
      iex> :ok = OddJob.perform(:test, fn -> send(parent, :hello) end)
      iex> receive do
      ...>   msg -> msg
      ...> end
      :hello
  """
  @spec perform(atom, fun) :: :ok
  def perform(pool, job) when is_atom(pool) and is_function(job) do
    GenServer.call(queue_id(pool), {:perform, job})
  end

  @doc """
  Returns the queue of the job `pool`.

  ## Examples

      iex> queue = OddJob.queue(:test)
      iex> is_struct(queue, OddJob.Queue)
      true
      iex> queue.id
      :odd_job_test_queue
  """
  @spec queue(atom) :: queue
  def queue(pool) when is_atom(pool) do
    queue_id(pool)
    |> OddJob.Queue.state()
  end

  @doc """
  Returns the ID of the job `pool`'s queue.

  ## Examples

      iex> OddJob.queue_id(:test)
      :odd_job_test_queue
  """
  @spec queue_id(atom) :: atom
  def queue_id(pool) when is_atom(pool), do: :"odd_job_#{pool}_queue"
end
