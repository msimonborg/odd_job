defmodule OddJob.MixProject do
  use Mix.Project

  def project do
    [
      app: :odd_job,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
end
