Code.require_file "../../../installer/test/mix_helper.exs", __DIR__

defmodule Phoenix.Dup do
end

defmodule Phoenix.Article do
  def __schema__(:source), do: "articles"
end

defmodule Mix.Tasks.Phoenix.Gen.ModelTest do
  use ExUnit.Case
  import MixHelper

  setup do
    Mix.Task.clear
    :ok
  end

  test "generates model" do
    in_tmp "generates model", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["user", "users", "name", "age:integer", "nicks:array:text",
                                       "famous:boolean", "born_at:naive_datetime", "secret:uuid", "desc:text",
                                       "blob:binary"]

      assert [migration] = Path.wildcard("priv/repo/migrations/*_create_user.exs")

      assert_file migration, fn file ->
        assert file =~ "defmodule Phoenix.Repo.Migrations.CreateUser do"
        assert file =~ "create table(:users) do"
        assert file =~ "add :name, :string"
        assert file =~ "add :age, :integer"
        assert file =~ "add :nicks, {:array, :text}"
        assert file =~ "add :famous, :boolean, default: false, null: false"
        assert file =~ "add :born_at, :naive_datetime"
        assert file =~ "add :secret, :uuid"
        assert file =~ "add :desc, :text"
        assert file =~ "add :blob, :binary"
        assert file =~ "timestamps()"
      end

      assert_file "web/models/user.ex", fn file ->
        assert file =~ "defmodule Phoenix.User do"
        assert file =~ "use Phoenix.Web, :model"
        assert file =~ "schema \"users\" do"
        assert file =~ "field :name, :string"
        assert file =~ "field :age, :integer"
        assert file =~ "field :nicks, {:array, :string}"
        assert file =~ "field :famous, :boolean, default: false"
        assert file =~ "field :born_at, :naive_datetime"
        assert file =~ "field :secret, Ecto.UUID"
        assert file =~ "field :desc, :string"
        assert file =~ "field :blob, :binary"
        assert file =~ "timestamps()"
        assert file =~ "def changeset"
        assert file =~ "[:name, :age, :nicks, :famous, :born_at, :secret, :desc, :blob]"
      end

      assert_file "test/models/user_test.exs", fn file ->
        assert file =~ "defmodule Phoenix.UserTest"
        assert file =~ "use Phoenix.ModelCase"

        assert file =~ ~S|@valid_attrs %{age: 42|
        assert file =~ ~S|changeset(%User{}, @valid_attrs)|
        assert file =~ ~S|assert changeset.valid?|

        assert file =~ ~S|@invalid_attrs %{}|
        assert file =~ ~S|changeset(%User{}, @invalid_attrs)|
        assert file =~ ~S|refute changeset.valid?|
      end
    end
  end

  test "generates nested model" do
    in_tmp "generates nested model", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Admin.User", "users", "name:string"]

      assert [migration] = Path.wildcard("priv/repo/migrations/*_create_admin_user.exs")

      assert_file migration, fn file ->
        assert file =~ "defmodule Phoenix.Repo.Migrations.CreateAdmin.User do"
        assert file =~ "create table(:users) do"
      end

      assert_file "web/models/admin/user.ex", fn file ->
        assert file =~ "defmodule Phoenix.Admin.User do"
        assert file =~ "use Phoenix.Web, :model"
        assert file =~ "schema \"users\" do"
      end
    end
  end

  test "generates belongs_to associations with association table provided by user" do
    in_tmp "generates belongs_to associations", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts", "title", "user_id:references:users"]

      assert [migration] = Path.wildcard("priv/repo/migrations/*_create_post.exs")

      assert_file migration, fn file ->
        assert file =~ "defmodule Phoenix.Repo.Migrations.CreatePost do"
        assert file =~ "create table(:posts) do"
        assert file =~ "add :title, :string"
        assert file =~ "add :user_id, references(:users, on_delete: :nothing)"
      end

      assert_file "web/models/post.ex", fn file ->
        assert file =~ "defmodule Phoenix.Post do"
        assert file =~ "use Phoenix.Web, :model"
        assert file =~ "schema \"posts\" do"
        assert file =~ "field :title, :string"
        assert file =~ "belongs_to :user, Phoenix.User"
      end
    end
  end

  test "generates belongs_to associations with foreign key provided by user" do
    in_tmp "generates belongs_to associations", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts", "title", "user:references:users"]

      assert [migration] = Path.wildcard("priv/repo/migrations/*_create_post.exs")

      assert_file migration, fn file ->
        assert file =~ "add :user_id, references(:users, on_delete: :nothing)"
      end

      assert_file "web/models/post.ex", fn file ->
        assert file =~ "belongs_to :user, Phoenix.User, foreign_key: :user_id"
      end
    end
  end

  test "generates unique_index" do
    in_tmp "generates unique_index", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts", "title:unique", "unique_int:integer:unique", "unique_float:float:unique"]

      assert [migration] = Path.wildcard("priv/repo/migrations/*_create_post.exs")

      assert_file migration, fn file ->
        assert file =~ "defmodule Phoenix.Repo.Migrations.CreatePost do"
        assert file =~ "create table(:posts) do"
        assert file =~ "add :title, :string"
        assert file =~ "add :unique_int, :integer"
        assert file =~ "add :unique_float, :float"
        assert file =~ "create unique_index(:posts, [:title])"
        assert file =~ "create unique_index(:posts, [:unique_int])"
        assert file =~ "create unique_index(:posts, [:unique_float])"
      end

      assert_file "web/models/post.ex", fn file ->
        assert file =~ "defmodule Phoenix.Post do"
        assert file =~ "use Phoenix.Web, :model"
        assert file =~ "schema \"posts\" do"
        assert file =~ "field :title, :string"
        assert file =~ "field :unique_int, :integer"
        assert file =~ "|> unique_constraint(:title)"
        assert file =~ "|> unique_constraint(:unique_int)"
      end
    end
  end

  test "generates indices on belongs_to associations" do
    in_tmp "generates indices on belongs_to associations", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts", "title", "user_id:references:users", "unique_post_id:references:posts:unique"]

      assert [migration] = Path.wildcard("priv/repo/migrations/*_create_post.exs")

      assert_file migration, fn file ->
        assert file =~ "defmodule Phoenix.Repo.Migrations.CreatePost do"
        assert file =~ "create table(:posts) do"
        assert file =~ "add :title, :string"
        assert file =~ "add :user_id, references(:users, on_delete: :nothing)"
        assert file =~ "add :unique_post_id, references(:posts, on_delete: :nothing)"
        assert file =~ "create index(:posts, [:user_id])"
        refute file =~ "create index(:posts, [:unique_post_id])"
        assert file =~ "create unique_index(:posts, [:unique_post_id])"
      end

      assert_file "web/models/post.ex", fn file ->
        assert file =~ "defmodule Phoenix.Post do"
        assert file =~ "use Phoenix.Web, :model"
        assert file =~ "schema \"posts\" do"
        assert file =~ "field :title, :string"
        assert file =~ "belongs_to :user, Phoenix.User"
        # assert file =~ "belongs_to :unique_post, Phoenix.UniquePost" # current behaviour, but perhaps not desired?
        assert file =~ "|> unique_constraint(:unique_post_id)"
      end
    end
  end

  test "generates migration with binary_id" do
    in_tmp "generates migration with binary_id", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts", "title", "user_id:references:users", "--binary-id"]

      assert [migration] = Path.wildcard("priv/repo/migrations/*_create_post.exs")

      assert_file migration, fn file ->
        assert file =~ "create table(:posts, primary_key: false) do"
        assert file =~ "add :id, :binary_id, primary_key: true"
        assert file =~ "add :user_id, references(:users, on_delete: :nothing, type: :binary_id)"
      end
    end
  end

  test "skips migration with --no-migration option" do
    in_tmp "skips migration with -no-migration option", fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts", "--no-migration"]

      assert [] = Path.wildcard("priv/repo/migrations/*_create_post.exs")
    end
  end

  test "uses defaults from :generators configuration" do
    in_tmp "uses defaults from generators configuration (migration)", fn ->
      with_generators_config [migration: false], fn ->
        Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts"]

        assert [] = Path.wildcard("priv/repo/migrations/*_create_post.exs")
      end
    end

    in_tmp "uses defaults from generators configuration (binary_id)", fn ->
      with_generators_config [binary_id: true], fn ->
        Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts"]

        assert [migration] = Path.wildcard("priv/repo/migrations/*_create_post.exs")

        assert_file migration, fn file ->
          assert file =~ "create table(:posts, primary_key: false) do"
          assert file =~ "add :id, :binary_id, primary_key: true"
        end
      end
    end
  end

  test "plural can't contain a colon" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Admin.User", "name:string", "foo:string"]
    end
  end

  test "plural can't have uppercased characters or camelized format" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Phoenix.Gen.Html.run ["Admin.User", "Users", "foo:string"]
    end

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Phoenix.Gen.Html.run ["Admin.User", "AdminUsers", "foo:string"]
    end
  end

  test "name is already defined" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Dup", "dups"]
    end
  end

  test "table name missing from references" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "posts", "user_id:references"]
    end
  end

  test "table name is not snake_case and lowercase" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post", "POSTS", "body:text"]
    end
  end

  test "table name omitted" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Phoenix.Gen.Model.run ["Post"]
    end
  end

  defp with_generators_config(config, fun) do
    old_value = Application.get_env(:phoenix, :generators, [])
    try do
      Application.put_env(:phoenix, :generators, config)
      fun.()
    after
      Application.put_env(:phoenix, :generators, old_value)
    end
  end
end
