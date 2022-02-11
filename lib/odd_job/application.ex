defmodule OddJob.Application do
  @moduledoc false
  @moduledoc since: "0.4.0"

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

      _ ->
        [{OddJob, OddJob.Job}]
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
