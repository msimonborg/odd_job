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
    default = Application.get_env(:odd_job, :default_pool)

    case default do
      false ->
        []

      nil ->
        [{OddJob, default_pool_name()}]

      other ->
        raise ArgumentError,
          message: """
          `:default_pool` cannot be renamed from `#{default_pool_name()}`. Use `false` as the value
          for `:default_pool` to disable default pools. Got `#{inspect(other)}`
          """
    end
  end

  defp default_pool_name, do: OddJob.Job

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
