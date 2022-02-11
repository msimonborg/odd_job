defmodule OddJob.CallbacksTest do
  use ExUnit.Case, async: false

  import OddJob, except: [child_spec: 1, start_link: 1]

  setup_all do
    {:ok, sup} = Supervisor.start_link([OddJob.CallbacksTest.Job], strategy: :one_for_one)
    %{sup: sup}
  end

  describe "module-based jobs" do
    defmodule Job do
      use OddJob
    end

    test "can be added to a supervision tree", %{sup: sup} do
      assert [{Job, _job_pid, :supervisor, [Job]}] = Supervisor.which_children(sup)
    end

    test "can perform work" do
      result = async_perform(Job, fn -> 10 ** 4 end) |> await()
      assert result == 10_000
    end

    test "ignores arguments to `start_link/1` if no custom function is defined" do
      message = ExUnit.CaptureIO.capture_io(:stderr, fn -> Job.start_link(:different_name) end)
      assert String.contains?(message, "Your initial argument was ignored") == true

      assert OddJob.whereis(:different_name) == nil
      pid = OddJob.whereis(Job)
      assert is_pid(pid)
    end
  end

  describe "start_link/1" do
    defmodule StartLinkJob do
      use OddJob

      def start_link(init_arg) do
        name = String.to_atom(init_arg)
        OddJob.start_link(name, pool_size: 10)
      end
    end

    test "can customize initialization of the job module" do
      {:ok, pid} = StartLinkJob.start_link("hello world")

      assert OddJob.Utils.supervisor_name("hello world") |> GenServer.whereis() == nil
      assert OddJob.Utils.supervisor_name(:"hello world") |> GenServer.whereis() == pid
      assert OddJob.workers(:"hello world") |> length() == 10
    end
  end

  describe "__using__/1" do
    defmodule UsingJob do
      use OddJob, restart: :temporary, shutdown: 5000
    end

    test "can configure the process start options" do
      assert %{
               id: UsingJob,
               start: {UsingJob, :start_link, [[]]},
               type: :supervisor,
               shutdown: 5000,
               restart: :temporary
             } == UsingJob.child_spec([])
    end
  end
end
