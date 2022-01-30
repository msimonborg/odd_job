defmodule OddJob.Async.ProxySupervisor do
  @moduledoc false
  use DynamicSupervisor

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  @spec init(any) ::
          {:ok,
           %{
             extra_arguments: list,
             intensity: non_neg_integer,
             max_children: :infinity | non_neg_integer,
             period: pos_integer,
             strategy: :one_for_one
           }}
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
