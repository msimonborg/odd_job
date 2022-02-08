defmodule OddJob.Async.ProxySupervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link(name) do
    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  @impl DynamicSupervisor
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
