defmodule OddJob.MixProject do
  use Mix.Project

  @version "0.5.1"
  @source_url "https://github.com/msimonborg/odd_job"

  def project do
    [
      app: :odd_job,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        odd_job: :test
      ],
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "OddJob",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, observer: :optional],
      mod: {OddJob.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.28", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.14.4", only: :test},
      {:mock, "~> 0.3.7", only: :test},
      {:receiver, "~> 0.2.2", only: :test}
    ]
  end

  defp description do
    "Simple job pools for Elixir OTP applications."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        Github: @source_url,
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "OddJob",
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html"],
      extras: ["CHANGELOG.md"],
      groups_for_modules: [
        "Public API": [
          OddJob
        ],
        "Internal Helpers": [
          OddJob.Utils
        ],
        "Data Types": [
          OddJob.Job
        ],
        Processes: [
          OddJob.Async.Proxy,
          OddJob.Async.ProxySupervisor,
          OddJob.Pool,
          OddJob.Pool.Supervisor,
          OddJob.Pool.Worker,
          OddJob.Queue,
          OddJob.Registry,
          OddJob.Scheduler,
          OddJob.Scheduler.Supervisor
        ]
      ]
    ]
  end
end
