defmodule OddJob.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Add job pools directly to your application supervision tree:
        # {OddJob, :email},
        # {OddJob, :task}
        OddJob.Async.ProxySupervisor,
        OddJob.Scheduler,
        {OddJob, :job}
      ] ++ pools()

    # if Mix.env() == :dev, do: :observer.start()
    opts = [strategy: :one_for_one, name: OddJob.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp pools do
    pools = Application.get_env(:odd_job, :supervise, [])
    for pool <- pools, do: {OddJob, pool}
  end
end
