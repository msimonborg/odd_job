defmodule OddJob.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Add job pools directly to your application supervision tree:
    #
    #   children = [
    #     {OddJob, :email},
    #     {OddJob, :task}
    #   ]
    #
    #   opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    #   Supervisor.start_link(children, opts)

    if Mix.env() == :dev, do: :observer.start()
    opts = [strategy: :one_for_one, name: OddJob.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  defp children() do
    pools = Application.get_env(:odd_job, :supervise, [])
    for pool <- pools, do: {OddJob, pool}
  end
end
