if Mix.env() == :test do
  defmodule Mix.Tasks.OddJob do
    @moduledoc false
    import IO.ANSI, only: [cyan: 0, bright: 0]
    alias Mix.Tasks.{Coveralls, Credo, Docs, Format}

    use Mix.Task

    @preferred_cli_env :test
    @required_elixir_version "1.13.0"

    @spec run(argv :: [String.t()]) :: nil
    def run(argv) do
      {opts, argv, _} = OptionParser.parse(argv, switches: [format: :boolean])
      if Keyword.get(opts, :format, true), do: run_formatter()
      do_run(argv)
    end

    @spec run_formatter :: any()
    def run_formatter do
      case Version.compare(System.version(), @required_elixir_version) do
        :lt ->
          raise RuntimeError, """
          #{bright()}Elixir version must be >= #{@required_elixir_version}. Detected version:
            * #{System.version()}
          Please upgrade to Elixir #{@required_elixir_version} or above to continue development on this project.
          """

        _ ->
          Mix.shell().info("#{cyan()}#{bright()}Running formatter")
          Format.run([])
      end
    end

    @spec do_run([binary()]) :: nil
    def do_run(argv) do
      Coveralls.Html.run(argv)
      Docs.run(argv)
      Credo.run(["--strict" | argv])
    end
  end
end
