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
  def handle_cast({:do_perform, job}, %{queue: queue} = state) do
    results = job.function.()
    GenServer.call(queue, {:complete, %{job | results: results, worker: self()}})
    {:noreply, state}
  end
end
