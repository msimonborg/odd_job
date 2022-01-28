defmodule OddJob.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :observer.start()

    # Add jobs directly to your application supervision tree
    # children = [
    #   {OddJob, :email},
    #   {OddJob, :task}
    # ]

    opts = [strategy: :one_for_one, name: OddJob.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  defp children() do
    jobs = Application.get_env(:odd_job, :supervise, [])
    for job <- jobs, do: {OddJob, job}
  end
end
