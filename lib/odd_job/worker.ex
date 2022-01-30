defmodule OddJob.Worker do
  @moduledoc false
  use GenServer

  defstruct [:id, :queue]

  @type t :: %__MODULE__{
          id: atom,
          queue: atom
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = struct(__MODULE__, opts)
    {:ok, state}
  end

  def child_spec(opts) do
    %{id: opts.id, start: {OddJob.Worker, :start_link, [opts]}}
  end

  @impl true
  def handle_cast({:do_perform, %{async: true, proxy: proxy} = job}, %{queue: queue} = state) do
    GenServer.call(proxy, :link_and_monitor)
    job = do_perform(queue, job)
    GenServer.call(proxy, {:complete, job})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:do_perform, job}, %{queue: queue} = state) do
    do_perform(queue, job)
    {:noreply, state}
  end

  defp do_perform(queue, job) do
    results = job.function.()
    GenServer.call(queue, :complete)
    %{job | results: results}
  end
end
