defmodule OddJob.Pool.Worker do
  @moduledoc """
  The `OddJob.Pool.Worker` is a `GenServer` that performs concurrent work as one of many
  members of an `OddJob.Pool`.

  The `OddJob.Pool.Worker` checks in with the pool and asks to be monitored upon startup. Once the worker is monitored
  it can start receiving jobs. In the unlikely event that the pool crashes, the worker will be notified
  and request to be monitored again when the pool restarts.
  """
  @moduledoc since: "0.1.0"

  use GenServer

  alias OddJob.Utils

  defstruct [:id, :pool, :pool_pid]

  @type t :: %__MODULE__{
          id: non_neg_integer,
          pool: atom,
          pool_pid: pid
        }

  @doc false
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: opts[:id])
  end

  @doc false
  def start_link(opts) do
    name = Utils.worker_name(opts[:pool], opts[:id])
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    pool_pid = Utils.pool_name(opts[:pool]) |> GenServer.whereis()
    state = struct(__MODULE__, opts ++ [pool_pid: pool_pid])
    Process.monitor(pool_pid)
    OddJob.Pool.monitor(pool_pid, self())
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:do_perform, %{async: true, proxy: proxy} = job}, %{pool: pool} = state) do
    GenServer.call(proxy, :link_and_monitor)
    job = do_perform(pool, job)
    GenServer.call(proxy, {:complete, job})
    {:noreply, state}
  end

  def handle_cast({:do_perform, job}, %{pool: pool} = state) do
    do_perform(pool, job)
    {:noreply, state}
  end

  defp do_perform(pool, job) do
    results = job.function.()

    Utils.pool_name(pool)
    |> GenServer.call(:complete)

    %{job | results: results}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{pool_pid: pool_pid} = state)
      when pid == pool_pid do
    pool_pid = check_for_new_pool_pid(state.pool)
    Process.monitor(pool_pid)
    OddJob.Pool.monitor(pool_pid, self())

    {:noreply, %{state | pool_pid: pool_pid}}
  end

  defp check_for_new_pool_pid(pool) do
    case Utils.pool_name(pool) |> GenServer.whereis() do
      nil -> check_for_new_pool_pid(pool)
      pid -> pid
    end
  end
end
