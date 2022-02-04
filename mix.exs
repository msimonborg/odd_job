defmodule OddJob.MixProject do
  use Mix.Project

  @version "0.3.1"

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
        "coveralls.travis": :test,
        "coveralls.safe_travis": :test,
        odd_job: :test
      ],
      description: description(),
      package: package(),
      source_url: "https://github.com/msimonborg/odd_job",
      homepage_url: "https://github.com/msimonborg/odd_job",
      name: "OddJob"
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
    "Job pools for Elixir OTP applications, written in Elixir."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/msimonborg/odd_job"}
    ]
  end
end
