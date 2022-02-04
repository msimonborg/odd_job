defmodule OddJob.Async.ProxyServer do
  @moduledoc false
  use GenServer, restart: :temporary
  import OddJob, only: [pool_id: 1]

  defstruct [:worker_ref, :job]

  @type t :: %__MODULE__{
          worker_ref: reference,
          job: job
        }

  @type job :: OddJob.t()

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
  def handle_call({:run, pool, job}, _from, state) do
    pool_id(pool)
    |> GenServer.call({:perform, job})

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
