defmodule Mix.Tasks.OddJobTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  import Mock
  alias Mix.Tasks.{Coveralls, Credo, Docs, Format, OddJob}

  describe "mix odd_job" do
    test "runs build task" do
      with_mocks([
        {Coveralls.Html, [], [run: fn _ -> nil end]},
        {Credo, [], [run: fn _ -> nil end]},
        {Docs, [], [run: fn _ -> nil end]}
      ]) do
        OddJob.run(["--no-format"])
        assert_called(Coveralls.Html.run([]))
        assert_called(Credo.run(["--strict"]))
        assert_called(Docs.run([]))
      end
    end

    test "runs the formatter when Elixir >= 1.13.0" do
      if Version.compare(System.version(), "1.13.0") != :lt do
        with_mock(Format, run: fn _ -> nil end) do
          assert capture_io(fn -> OddJob.run_formatter() end)
                 |> String.contains?("Running formatter")

          assert_called(Format.run([]))
        end
      else
        assert_raise RuntimeError, ~r/Elixir version must be >= 1.13/, fn ->
          OddJob.run_formatter()
        end
      end
    end
  end
end
