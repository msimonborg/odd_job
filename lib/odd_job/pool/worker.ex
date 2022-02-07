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

  defstruct [:id, :pool, :pool_id]

  @type t :: %__MODULE__{
          id: atom,
          pool: atom,
          pool_id: atom
        }

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:id])
  end

  @impl GenServer
  def init(opts) do
    state = struct(__MODULE__, opts)
    Process.monitor(state.pool_id)
    OddJob.Pool.monitor(state.pool_id, self())
    {:ok, state}
  end

  @doc false
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: opts[:id])
  end

  @impl GenServer
  def handle_cast({:do_perform, %{async: true, proxy: proxy} = job}, %{pool_id: pool_id} = state) do
    GenServer.call(proxy, :link_and_monitor)
    job = do_perform(pool_id, job)
    GenServer.call(proxy, {:complete, job})
    {:noreply, state}
  end

  def handle_cast({:do_perform, job}, %{pool_id: pool_id} = state) do
    do_perform(pool_id, job)
    {:noreply, state}
  end

  defp do_perform(pool_id, job) do
    results = job.function.()
    GenServer.call(pool_id, :complete)
    %{job | results: results}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, {proc, _}, _reason}, %{pool_id: pool_id} = state) do
    if proc == pool_id do
      Process.monitor(pool_id)
      OddJob.Pool.monitor(pool_id, self())
    end

    {:noreply, state}
  end
end
