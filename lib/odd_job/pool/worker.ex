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

  alias OddJob.{Async.Proxy, Queue}

  defstruct [:id, :pool, :queue_pid, :queue_name]

  @type t :: %__MODULE__{
          id: non_neg_integer,
          pool: atom,
          queue_pid: pid,
          queue_name: OddJob.Queue.queue_name()
        }

  @type job :: OddJob.Job.t()

  # <---- Client API ---->

  @doc false
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: opts[:id])
  end

  @doc false
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts)

  @doc false
  @spec perform(pid, job) :: :ok
  def perform(worker, job),
    do: GenServer.cast(worker, {:perform, job})

  # <---- Callbacks ---->

  @impl GenServer
  @spec init(keyword) :: {:ok, t}
  def init(opts) do
    pool = Keyword.fetch!(opts, :pool)

    with queue_name = {:via, _, _} <- OddJob.queue_name(pool),
         queue_pid when is_pid(queue_pid) <- GenServer.whereis(queue_name) do
      Process.monitor(queue_pid)
      Queue.monitor_worker(queue_name, self())
      {:ok, struct(__MODULE__, opts ++ [queue_pid: queue_pid, queue_name: queue_name])}
    else
      _ -> raise RuntimeError, message: "#{inspect(pool)} queue process cannot be found"
    end
  end

  @impl GenServer
  def handle_cast({:perform, %{async: true, proxy: proxy} = job}, state) do
    {:ok, _} = Proxy.link_and_monitor_caller(proxy)
    job = do_perform(state.queue_name, job)
    Proxy.report_completed_job(proxy, job)
    {:noreply, state}
  end

  def handle_cast({:perform, job}, state) do
    do_perform(state.queue_name, job)
    {:noreply, state}
  end

  defp do_perform(queue_name, job) do
    results = job.function.()
    Queue.request_new_job(queue_name, self())
    %{job | results: results}
  end

  @impl GenServer
  def handle_info({:DOWN, _, _, pid, _}, %{queue_pid: q_pid} = state) when pid == q_pid do
    q_name = state.queue_name
    new_q_pid = check_for_new_queue_process(q_name)
    Process.monitor(new_q_pid)
    Queue.monitor_worker(q_name, self())
    {:noreply, %{state | queue_pid: new_q_pid}}
  end

  defp check_for_new_queue_process(queue_name) do
    case GenServer.whereis(queue_name) do
      nil -> check_for_new_queue_process(queue_name)
      pid -> pid
    end
  end
end
