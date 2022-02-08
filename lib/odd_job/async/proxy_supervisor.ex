defmodule OddJob.Async.ProxySupervisor do
  @moduledoc false
  @moduledoc since: "0.4.0"
  use DynamicSupervisor

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
