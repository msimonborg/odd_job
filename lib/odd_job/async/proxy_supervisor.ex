defmodule OddJob.Async.ProxySupervisor do
  @moduledoc """
  The `OddJob.Async.ProxySupervisor` is a `DynamicSupervisor` that starts and stops children
  `OddJob.Async.Proxy` processes.
  """
  @moduledoc since: "0.4.0"

  @doc false
  use DynamicSupervisor

  alias OddJob.Utils

  @child OddJob.Async.Proxy

  @spec start_child(atom) :: pid
  def start_child(pool) do
    pool
    |> Utils.scheduler_sup_name()
    |> DynamicSupervisor.start_child(@child)
    |> Utils.extract_pid()
  end

  @doc false
  def start_link(name),
    do: DynamicSupervisor.start_link(__MODULE__, [], name: Utils.proxy_sup_name(name))

  @impl DynamicSupervisor
  def init([]),
    do: DynamicSupervisor.init(strategy: :one_for_one)
end
