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

  defstruct [:id, :pool, :queue_pid, :queue_name]

  @type t :: %__MODULE__{
          id: non_neg_integer,
          pool: atom,
          queue_pid: pid,
          queue_name: OddJob.Queue.queue_name()
        }

  @doc false
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: opts[:id])
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    pool = Keyword.fetch!(opts, :pool)

    with queue_name = {:via, _, _} <- OddJob.queue_name(pool),
         queue_pid when is_pid(queue_pid) <- GenServer.whereis(queue_name) do
      state = struct(__MODULE__, opts ++ [queue_pid: queue_pid, queue_name: queue_name])
      Process.monitor(queue_pid)
      OddJob.Queue.monitor_worker(queue_name, self())
      {:ok, state}
    else
      _ -> raise RuntimeError, message: "#{inspect(pool)} queue process cannot be found"
    end
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

    pool
    |> Utils.queue_name()
    |> GenServer.cast({:complete, self()})

    %{job | results: results}
  end

  @impl GenServer
  def handle_info({:DOWN, _, _, pid, _}, %{queue_pid: queue_pid, queue_name: queue_name} = state)
      when pid == queue_pid do
    new_queue_pid = check_for_new_queue_process(queue_name)
    Process.monitor(new_queue_pid)
    OddJob.Queue.monitor_worker(queue_name, self())
    {:noreply, %{state | queue_pid: new_queue_pid}}
  end

  defp check_for_new_queue_process(queue_name) do
    case GenServer.whereis(queue_name) do
      nil -> check_for_new_queue_process(queue_name)
      pid -> pid
    end
  end
end
