defmodule OddJob.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Registry, name: OddJob.SchedulerRegistry, keys: :unique},
        {DynamicSupervisor, strategy: :one_for_one, name: OddJob.Async.ProxySupervisor},
        {DynamicSupervisor, strategy: :one_for_one, name: OddJob.SchedulerSupervisor}
      ] ++ default_pool() ++ extra_pools()

    # if Mix.env() == :dev, do: :observer.start()
    opts = [strategy: :one_for_one, name: OddJob.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp default_pool do
    default = Application.get_env(:odd_job, :default_pool, :job)

    case default do
      false ->
        []

      default when is_atom(default) and default != true ->
        [{OddJob, default}]

      _ ->
        raise ArgumentError,
          message: """
          `:default_pool` in :odd_job config must be either an atom naming the pool (e.g. `:work`) or else the value `false`
          """
    end
  end

  defp extra_pools do
    extra_pools = Application.get_env(:odd_job, :extra_pools, [])
    for pool <- extra_pools, do: {OddJob, pool}
  end
end
