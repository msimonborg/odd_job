defmodule OddJob.Async.ProxyServer do
  @moduledoc false
  use GenServer
  import OddJob, only: [queue_id: 1]
  alias OddJob.Job

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  @spec init(any) :: {:ok, any}
  def init(init_arg) do
    {:ok, init_arg}
  end

  @impl true
  def handle_call({:run, ref, pool, fun}, {from, _}, state) do
    job = %Job{ref: ref, function: fun, owner: from, async: true}
    GenServer.call(queue_id(pool), {:perform_async, job})
    {:reply, job, state}
  end
end
