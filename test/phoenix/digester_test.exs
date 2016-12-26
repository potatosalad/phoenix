defmodule Phoenix.DigesterTest do
  use ExUnit.Case, async: true

  @output_path Path.join("tmp", "phoenix_digest")
  @fake_now 32132173
  @hash_regex ~S"[a-fA-F\d]{32}"

  setup do
    File.rm_rf!(@output_path)
    :ok
  end

  describe "compile" do
    test "fails when the given paths are invalid" do
      assert {:error, :invalid_path} = Phoenix.Digester.compile("nonexistent path", "/ ?? /path")
    end

    test "digests and compress files" do
      input_path = "test/fixtures/digest/priv/static/"
      assert :ok = Phoenix.Digester.compile(input_path, @output_path)
      output_files = assets_files(@output_path)

      assert "phoenix.png" in output_files
      refute "phoenix.png.gz" in output_files
      assert "app.js" in output_files
      assert "app.js.gz" in output_files
      assert "css/app.css" in output_files
      assert "css/app.css.gz" in output_files
      assert "manifest.json" in output_files
      assert Enum.any?(output_files, &(String.match?(&1, ~r/(phoenix-#{@hash_regex}\.png)/)))
      refute Enum.any?(output_files, &(String.match?(&1, ~r/(phoenix-#{@hash_regex}\.png\.gz)/)))

      json =
        Path.join(@output_path, "manifest.json")
        |> File.read!()
        |> Poison.decode!()

      assert json["latest"]["phoenix.png"] =~ ~r"phoenix-#{@hash_regex}.png"
      assert json["version"] == 1
    end

    test "includes existing digests in new manifest" do
      source_path = "test/fixtures/digest/priv/static/"
      input_path = "tmp/digest/static"
      :ok = File.mkdir_p!(@output_path)
      :ok = File.mkdir_p!(input_path)
      {:ok, _} = File.cp_r(source_path, input_path)
      :ok = File.cp("test/fixtures/manifest.json", Path.join(@output_path, "manifest.json"))

      assert :ok = Phoenix.Digester.compile(input_path, @output_path)

      json =
        Path.join(@output_path, "manifest.json")
        |> File.read!()
        |> Poison.decode!()

      # Keep old entries
      assert json["digests"]["foo-d978852bea6530fcd197b5445ed008fd.css"]["logical_path"] == "foo.css"

      # Add new entries
      key = Enum.find(Map.keys(json["digests"]), &(&1 =~ ~r"phoenix-#{@hash_regex}.png"))
      assert json["digests"][key]["logical_path"] == "phoenix.png"
      assert is_integer(json["digests"][key]["mtime"])
      assert json["digests"][key]["size"] == 13900
      assert json["digests"][key]["digest"] =~ ~r"#{@hash_regex}"
      assert json["version"] == 1
    end

    test "digests and compress nested files" do
      input_path = "test/fixtures/digest/priv/"
      assert :ok = Phoenix.Digester.compile(input_path, @output_path)

      output_files = assets_files(@output_path)

      assert "static/phoenix.png" in output_files
      refute "static/phoenix.png.gz" in output_files
      assert "manifest.json" in output_files
      assert Enum.any?(output_files, &(String.match?(&1, ~r/(phoenix-#{@hash_regex}\.png)/)))
      refute Enum.any?(output_files, &(String.match?(&1, ~r/(phoenix-#{@hash_regex}\.png\.gz)/)))

      json =
        Path.join(@output_path, "manifest.json")
        |> File.read!()
        |> Poison.decode!()
      assert json["latest"]["static/phoenix.png"] =~ ~r"static/phoenix-#{@hash_regex}\.png"
    end

    test "doesn't duplicate files when digesting and compressing twice" do
      input_path = Path.join("tmp", "phoenix_digest_twice")
      input_file = Path.join(input_path, "file.js")

      File.rm_rf!(input_path)
      File.mkdir_p!(input_path)
      File.write!(input_file, "console.log('test');")

      assert :ok = Phoenix.Digester.compile(input_path, input_path)
      assert :ok = Phoenix.Digester.compile(input_path, input_path)

      output_files = assets_files(input_path)

      refute "file.js.gz.gz" in output_files
      refute "manifest.json.gz" in output_files
      refute Enum.any?(output_files, & &1 =~ ~r/file-#{@hash_regex}.[\w|\d]*.[-#{@hash_regex}/)
    end

    test "digests only absolute and relative asset paths found within stylesheets" do
      input_path = "test/fixtures/digest/priv/static/"
      assert :ok = Phoenix.Digester.compile(input_path, @output_path)

      digested_css_filename =
        assets_files(@output_path)
        |> Enum.find(&(&1 =~ ~r"app-#{@hash_regex}.css"))

      digested_css =
        Path.join(@output_path, digested_css_filename)
        |> File.read!()

      refute digested_css =~ ~r"/phoenix\.png"
      refute digested_css =~ ~r"\.\./images/relative\.png"
      assert digested_css =~ ~r"/phoenix-#{@hash_regex}\.png\?vsn=d"
      assert digested_css =~ ~r"\.\./images/relative-#{@hash_regex}\.png\?vsn=d"

      refute digested_css =~ ~r"http://www.phoenixframework.org/absolute-#{@hash_regex}.png"
      assert digested_css =~ ~r"http://www.phoenixframework.org/absolute.png"
    end

    test "digests sourceMappingURL asset paths found within javascript source files" do
      input_path = "test/fixtures/digest/priv/static/"
      assert :ok = Phoenix.Digester.compile(input_path, @output_path)

      digested_js_map_filename =
        assets_files(@output_path)
        |> Enum.find(&(&1 =~ ~r"app.js-#{@hash_regex}.map"))

      digested_js_filename =
        assets_files(@output_path)
        |> Enum.find(&(&1 =~ ~r"app-#{@hash_regex}.js"))

      digested_js =
        Path.join(@output_path, digested_js_filename)
        |> File.read!()

      refute digested_js =~ ~r"app.js.map"
      assert digested_js =~ ~r"#{digested_js_map_filename}$"
    end

    test "digests file url paths found within javascript mapping files" do
      input_path = "test/fixtures/digest/priv/static/"
      assert :ok = Phoenix.Digester.compile(input_path, @output_path)

      digested_js_map_filename =
        assets_files(@output_path)
        |> Enum.find(&(&1 =~ ~r"app.js-#{@hash_regex}.map"))

      digested_js_filename =
        assets_files(@output_path)
        |> Enum.find(&(&1 =~ ~r"app-#{@hash_regex}.js"))

      digested_js_map =
        Path.join(@output_path, digested_js_map_filename)
        |> File.read!()

      refute digested_js_map =~ ~r"\"file\":\"app.js\""
      assert digested_js_map =~ ~r"#{digested_js_filename}"
    end

    test "does not digest assets within undigested files" do
      input_path = "test/fixtures/digest/priv/static/"
      assert :ok = Phoenix.Digester.compile(input_path, @output_path)

      undigested_css =
        Path.join(@output_path, "css/app.css")
        |> File.read!()

      assert undigested_css =~ ~r"/phoenix\.png"
      assert undigested_css =~ ~r"\.\./images/relative\.png"
      refute undigested_css =~ ~r"/phoenix-#{@hash_regex}\.png"
      refute undigested_css =~ ~r"\.\./images/relative-#{@hash_regex}\.png"
    end
  end

  describe "clean" do
    test "fails when the given path is invalid" do
      assert {:error, :invalid_path} = Phoenix.Digester.clean("nonexistent path", 3600, 2)
    end

    test "removes versions over the keep count" do
      manifest_path = "test/fixtures/digest/cleaner/manifest.json"
      File.mkdir_p!(@output_path)
      File.cp(manifest_path, "#{@output_path}/manifest.json")
      File.touch("#{@output_path}/app.css")
      File.touch("#{@output_path}/app-1.css")
      File.touch("#{@output_path}/app-1.css.gz")
      File.touch("#{@output_path}/app-2.css")
      File.touch("#{@output_path}/app-2.css.gz")
      File.touch("#{@output_path}/app-3.css")
      File.touch("#{@output_path}/app-3.css.gz")
      File.touch("#{@output_path}/app.css")

      assert :ok = Phoenix.Digester.clean(@output_path, 3600, 1, @fake_now)
      output_files = assets_files(@output_path)

      assert "app.css" in output_files
      assert "app-3.css" in output_files
      assert "app-3.css.gz" in output_files
      assert "app-2.css" in output_files
      assert "app-2.css.gz" in output_files
      refute "app-1.css" in output_files
      refute "app-1.css.gz" in output_files
    end

    test "removes files older than specified number of seconds" do
      manifest_path = "test/fixtures/digest/cleaner/manifest.json"

      File.mkdir_p!(@output_path)
      File.cp(manifest_path, "#{@output_path}/manifest.json")
      File.touch("#{@output_path}/app.css")
      File.touch("#{@output_path}/app-1.css")
      File.touch("#{@output_path}/app-1.css.gz")
      File.touch("#{@output_path}/app-2.css")
      File.touch("#{@output_path}/app-2.css.gz")
      File.touch("#{@output_path}/app-3.css")
      File.touch("#{@output_path}/app-3.css.gz")
      File.touch("#{@output_path}/app.css")

      assert :ok = Phoenix.Digester.clean(@output_path, 1, 10, @fake_now)
      output_files = assets_files(@output_path)

      assert "app.css" in output_files
      assert "app-2.css" in output_files
      assert "app-2.css.gz" in output_files
      assert "app-3.css" in output_files
      assert "app-3.css.gz" in output_files
      refute "app-1.css" in output_files
      refute "app-1.css.gz" in output_files
    end
  end

  defp assets_files(path) do
    path
    |> Path.join("**/*")
    |> Path.wildcard
    |> Enum.filter(&(!File.dir?(&1)))
    |> Enum.map(&(Path.relative_to(&1, path)))
  end
end
