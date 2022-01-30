defmodule OddJob.Async.ProxyServer do
  @moduledoc false
  use GenServer
  import OddJob, only: [queue_id: 1]

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
  def handle_call({:run, pool, job}, _from, _state) do
    queue_id(pool)
    |> GenServer.call({:perform_async, job})

    {:reply, job, job}
  end
end
