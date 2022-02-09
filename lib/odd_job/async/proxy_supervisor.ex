defmodule OddJob.Async.ProxySupervisor do
  @moduledoc """
  The `OddJob.Async.ProxySupervisor` is a `DynamicSupervisor` that starts and stops children
  `OddJob.Async.Proxy` processes.
  """
  @moduledoc since: "0.4.0"

  @doc false
  use DynamicSupervisor

  @doc false
  def start_link(name) do
    opts = [
      name: OddJob.Utils.proxy_sup_name(name)
    ]

    DynamicSupervisor.start_link(__MODULE__, [], opts)
  end

  @impl DynamicSupervisor
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
