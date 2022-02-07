defmodule OddJob.Async.ProxyServer do
  @moduledoc """
  The `OddJob.Async.ProxyServer` links the job caller to the worker as the job is being performed.

  The process that calls `async_perform/2` or `async_perform_many/3` must link and monitor the worker
  performing the job so it can receive the results and be notified of failure by exiting or
  receiving an `:EXIT` message if the process is trapping exits. However, at the time the function is
  called it is unknown which worker will receive the job and when. The proxy is a process that is
  created to provide a link between the caller and the worker.

  When an async funcion is called, the caller links and monitors the proxy, and the proxy `pid` and
  monitor `reference` are stored in the `OddJob.Job` struct. When the worker receives the job it calls
  the proxy to be linked and monitored. Job results as well as `:EXIT` and `:DOWN` messages are passed
  from the worker to the caller via the proxy.
  """
  @moduledoc since: "0.1.0"

  @doc false
  use GenServer, restart: :temporary

  defstruct [:worker_ref, :job]

  @type t :: %__MODULE__{
          worker_ref: reference,
          job: job
        }

  @type job :: OddJob.Job.t()

  @doc false
  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  @spec init(any) :: {:ok, any}
  def init(_init_arg) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:job, job}, state), do: {:noreply, %{state | job: job}}

  @impl true
  def handle_call({:run, pool, job}, _from, state) do
    GenServer.cast(pool, {:perform, job})

    {:reply, job, %{state | job: job}}
  end

  @impl true
  def handle_call(:link_and_monitor, {from, _}, state) do
    Process.link(from)
    ref = Process.monitor(from)
    {:reply, :ok, %{state | worker_ref: ref}}
  end

  @impl true
  def handle_call({:complete, job}, {from, _}, %{worker_ref: ref} = state) do
    Process.unlink(from)
    Process.demonitor(ref, [:flush])
    Process.send(job.owner, {job.ref, job.results}, [])
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{worker_ref: worker_ref} = state)
      when ref == worker_ref do
    {:stop, reason, state}
  end
end
