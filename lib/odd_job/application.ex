defmodule OddJob.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children =
      [
        OddJob.Registry
      ] ++ default_pool() ++ extra_pools()

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

    for pool <- extra_pools do
      start_arg =
        case pool do
          {name, opts} when is_atom(name) and is_list(opts) ->
            Keyword.put(opts, :name, name)

          name when is_atom(name) ->
            name
        end

      {OddJob, start_arg}
    end
  end
end
