defmodule OddJob.Scheduler.Supervisor do
  @moduledoc """
  The `OddJob.Scheduler.Supervisor` is a `DynamicSupervisor` that starts and stops children
  `OddJob.Scheduler` processes.
  """
  @moduledoc since: "0.4.0"

  @doc false
  use DynamicSupervisor

  alias OddJob.Utils

  @child OddJob.Scheduler

  @spec start_child(atom) :: pid
  def start_child(pool) do
    pool
    |> Utils.scheduler_sup_name()
    |> DynamicSupervisor.start_child(@child)
    |> Utils.extract_pid()
  end

  @doc false
  def start_link(name) do
    opts = [
      name: OddJob.Utils.scheduler_sup_name(name)
    ]

    DynamicSupervisor.start_link(__MODULE__, [], opts)
  end

  @impl DynamicSupervisor
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
