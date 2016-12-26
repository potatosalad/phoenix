Code.require_file "../../../installer/lib/phx_new/generator.ex", __DIR__
Code.require_file "../../../installer/lib/phx_new/single.ex", __DIR__
Code.require_file "../../../installer/lib/phx_new/umbrella.ex", __DIR__
Code.require_file "../../../installer/lib/phx_new.ex", __DIR__
Code.require_file "../../../installer/test/mix_helper.exs", __DIR__

# Here we test the installer is up to date.
defmodule Mix.Tasks.Phx.NewTest do
  use ExUnit.Case
  use RouterHelper

  import MixHelper
  import ExUnit.CaptureIO

  @epoch {{1970, 1, 1}, {0, 0, 0}}

  setup do
    # The shell asks to install npm and mix deps.
    # We will politely say not.
    send self(), {:mix_shell_input, :yes?, false}
    send self(), {:mix_shell_input, :yes?, false}
    :ok
  end

  test "bootstraps generated project" do
    Logger.disable(self())

    Application.put_env(:phx_blog, PhxBlog.Web.Endpoint,
      secret_key_base: String.duplicate("abcdefgh", 8),
      code_reloader: true)

    in_tmp "bootstrap", fn ->
      Mix.Tasks.Phx.New.run(["phx_blog", "--no-brunch", "--no-ecto"])
    end

    # Copy artifacts from Phoenix so we can compile and run tests
    File.cp_r "_build",   "bootstrap/phx_blog/_build"
    File.cp_r "deps",     "bootstrap/phx_blog/deps"
    File.cp_r "mix.lock", "bootstrap/phx_blog/mix.lock"

    in_project :phx_blog, Path.join(tmp_path(), "bootstrap/phx_blog"), fn _ ->
      Mix.Task.clear()
      Mix.Task.run "compile", ["--no-deps-check"]
      assert_received {:mix_shell, :info, ["Generated phx_blog app"]}
      refute_received {:mix_shell, :info, ["Generated phoenix app"]}
      Mix.shell.flush()

      # Adding a new template touches file (through mix)
      File.touch! "lib/web/views/layout_view.ex", @epoch
      File.write! "lib/web/templates/layout/another.html.eex", "oops"

      Mix.Task.clear()
      Mix.Task.run "compile", ["--no-deps-check"]
      assert File.stat!("lib/web/views/layout_view.ex").mtime > @epoch

      # Adding a new template triggers recompilation (through request)
      File.touch! "lib/web/views/page_view.ex", @epoch
      File.write! "lib/web/templates/page/another.html.eex", "oops"

      {:ok, _} = Application.ensure_all_started(:phx_blog)
      PhxBlog.Web.Endpoint.call(conn(:get, "/"), [])
      assert File.stat!("lib/web/views/page_view.ex").mtime > @epoch

      # Ensure /priv static files are copied
      assert File.exists?("priv/static/js/phoenix.js")

      # We can run tests too, starting the app.
      assert capture_io(fn ->
        capture_io(:user, fn ->
          Mix.Task.run("test", ["--no-start", "--no-compile"])
        end)
      end) =~ ~r"4 tests, 0 failures"
    end
  end

  defp in_project(app, path, fun) do
    %{name: name, file: file} = Mix.Project.pop

    try do
      capture_io :stderr, fn ->
        Mix.Project.in_project app, path, [], fun
      end
    after
      Mix.Project.push name, file
    end
  end
end
