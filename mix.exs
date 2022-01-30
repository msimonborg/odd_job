defmodule OddJob.MixProject do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      app: :odd_job,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
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
