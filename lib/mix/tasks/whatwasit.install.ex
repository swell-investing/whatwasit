defmodule Mix.Tasks.Whatwasit.Install do
  @moduledoc """
  Setup the Whatwasit package for your application.

  Adds a migration for the Version model used to trackage changes to
  the desired models.

  Prints example configuration that should be added to your
  config/config.exs file.

  ## Examples

      # create the migration and print configuration
      mix whatwasit.install

      # print configuration
      mix whatwasit.install --no-migrations

      # Add current user tracking
      mix whatwasit.install --whodoneit

      # use a different user model
      mix whatwasit.install --whodoneit --model="Account accounts"

      # use a simple whodoneit_id field
      mix whatwasit.install --whodoneit-id=integer

      # store the whodoneit model in a map
      mix whatwasit.install --whodoneit-map

      # set the whodoneit model foreign key type to uuid
      mix whatwasit.install --whodoneit-id-type=uuid

  The following options are available:

  * `--model` -- The authentication model and table_name
  * `--repo` -- The project's repo if different than the standard default
  * `--module` -- The projects base module
  * `--migration-path` -- The migration path
  * `--whodoneit` -- Add current user tracking
  * `--whodoneit-id` -- Use a simple id field instead of a relationship
  * `--whodoneit-map` -- Store the current_user as a map
  * `--whodoneit-id-type` -- Set the foreign key type

  The following options are available to disable features:

  * `--no-migrations` -- Don't generate the migration
  * `--no-boilerplate` -- Don't generate anything
  * `--no-models` -- Dont' generate models
  """

  @shortdoc "Configure the Whatwasit Package"

  import Macro, only: [camelize: 1, underscore: 1]
  import Mix.Generator
  import Mix.Ecto
  import Whatwasit.Mix.Utils

  @default_options ~w()
  # the options that default to true, and can be disabled with --no-option
  @default_booleans  ~w(config migrations boilerplate models)

  # all boolean_options
  @boolean_options   @default_booleans

  @switches [repo: :string, migration_path: :string, model: :string, module: :string, whodoneit: :boolean, whodoneit_id: :string, whodoneit_map: :boolean, whodoneit_id_type: :string] ++ Enum.map(@boolean_options, &({String.to_atom(&1), :boolean}))
  @switch_names Enum.map(@switches, &(elem(&1, 0)))


  def run(args) do
    {opts, parsed, unknown} = OptionParser.parse(args, switches: @switches)

    verify_args!(parsed, unknown)

    {bin_opts, opts} = parse_options(opts)

    do_config(opts, bin_opts)
    |> do_run
  end

  def do_run(config) do
    config
    |> gen_migration
    |> gen_version_model
    |> print_instructions
  end

  defp gen_version_model(%{models: true, whodoneit_map: true, boilerplate: true, base: base} = config) do
    changeset_fields = "~w(item_type item_id object action whodoneit)a"
    schema_fields = "field :whodoneit, :map\n"
    binding = [
      base: base,
      schema_fields: schema_fields,
      changeset_fields: changeset_fields
    ]
    copy_from paths(),
      "priv/templates/whatwasit.install/models/whatwasit", "", binding, [
        {:eex, "version_map.ex", "web/models/whatwasit/version.ex"},
      ]
    config
  end

  defp copy_from(apps, source_dir, target_dir, binding, mapping) when is_list(mapping) do
    roots = Enum.map(apps, &to_app_source(&1, source_dir))

    for {format, source_file_path, target_file_path} <- mapping do
      source =
        Enum.find_value(roots, fn root ->
          source = Path.join(root, source_file_path)
          if File.exists?(source), do: source
        end) || raise "could not find #{source_file_path} in any of the sources"

      target = Path.join(target_dir, target_file_path)

      contents =
        case format do
          :text -> File.read!(source)
          :eex  -> EEx.eval_file(source, binding)
        end

      Mix.Generator.create_file(target, contents)
    end
  end

  defp to_app_source(path, source_dir) when is_binary(path),
    do: Path.join(path, source_dir)
  defp to_app_source(app, source_dir) when is_atom(app),
    do: Application.app_dir(app, source_dir)

  defp gen_version_model(%{models: true, boilerplate: true, base: base} = config) do
    name_field = "field :whodoneit_name, :string\n"
    changeset_fields = "item_type item_id object action"
    whodoneit_changeset_fields = " whodoneit_id whodoneit_name"
    whodoneit_id = config[:whodoneit_id]
    whodoneit = config[:whodoneit]
    {schema_fields, add_changeset_fields} = cond do
      config[:whodoneit_id_type] ->
        {name_field <> "    belongs_to :whodoneit, #{config[:user_schema] |> elem(0)}, type: Ecto.UUID\n", whodoneit_changeset_fields}
      whodoneit_id ->
        {name_field <> "    field :whodoneit_id, :#{whodoneit_id}\n", whodoneit_changeset_fields}
      whodoneit ->
        {name_field <> "    belongs_to :whodoneit, #{config[:user_schema] |> elem(0)}\n", whodoneit_changeset_fields}
      true ->
        {"", ""}
    end
    binding = [
      base: base,
      schema_fields: schema_fields,
      changeset_fields: "~w(#{changeset_fields}#{add_changeset_fields})a"
    ]
    copy_from paths(),
      "priv/templates/whatwasit.install/models/whatwasit", "", binding, [
        {:eex, "version.ex", "web/models/whatwasit/version.ex"},
      ]
    config
  end
  defp gen_version_model(config) do
    config
  end

  defp gen_migration(%{migrations: true, boilerplate: true} = config) do
    {_, table_name} = config[:user_schema]
    whodoneit = cond do
      config[:whodoneit_id_type] ->
        """
              add :whodoneit_name, :string
              add :whodoneit_id, references(:#{table_name}, on_delete: :nilify_all, type: :uuid)
        """
      config[:whodoneit_map] ->
        """
              add :whodoneit, :map
        """
      config[:whodoneit_id] ->
        """
              add :whodoneit_name, :string
              add :whodoneit_id, :#{config[:whodoneit_id]}
        """
      config[:whodoneit] ->
        """
              add :whodoneit_name, :string
              add :whodoneit_id, references(:#{table_name}, on_delete: :nilify_all)
        """
      true -> ""
    end
    do_gen_migration config, "create_whatwasit_version", fn repo, _path, file, name ->

      change = """
          create table(:versions) do
            add :item_type, :string, null: false
            add :item_id, :integer, null: false
            add :action, :string
            add :object, :map, null: false
      """ <> whodoneit <> """
            timestamps
          end
      """
      assigns = [mod: Module.concat([repo, Migrations, camelize(name)]),
                       change: change]
      create_file file, migration_template(assigns)
    end
  end
  defp gen_migration(config), do: config

  defp do_gen_migration(config, name, fun) do
    timestamp = timestamp()
    repo = config[:repo]
    |> String.split(".")
    |> Module.concat
    ensure_repo(repo, [])
    path = case config[:migration_path] do
      path when is_binary(path) -> path
      _ ->
        Path.relative_to(Ecto.Migrator.migrations_path(repo), Mix.Project.app_path)
    end
    file = Path.join(path, "#{timestamp}_#{underscore(name)}.exs")
    fun.(repo, path, file, name)
    config
  end

  defp print_instructions(%{whodoneit_id: type} = config) when type != nil do
    Mix.shell.info """
    Add the following to your config/config.exs:

      config :whatwasit,
        repo: #{config[:repo]},
        whodoneit_id: :#{type}

    """ <> default_model_instructions(config)
    config
  end
  defp print_instructions(%{whodoneit: true, base: base} = config) do
    Mix.shell.info """
    Add the following to your config/config.exs:

      config :whatwasit,
        repo: #{config[:repo]}


    Update your models so the look like this:

      defmodule #{base}.Post do
        use #{base}.Web, :model
        use Whatwasit         # add this

        schema "posts" do
          field :title, :string
          field :body, :string
          timestamps
        end

        def changeset(model, params \\ %{}, opts \\ []) do
          model
          |> cast(params, ~w(title body)a)
          |> validate_required(~w(title body)a)
          |> prepare_version(opts)   # add this
        end
      end
    """
    config
  end
  defp print_instructions(config) do
    Mix.shell.info """
    Add the following to your config/config.exs:

      config :whatwasit,
        repo: #{config[:repo]}

    """ <> default_model_instructions(config)
    config
  end
  defp default_model_instructions(%{base: base}) do
    """
    Update your models like this:

      defmodule #{base}.Post do
        use #{base}.Web, :model
        use Whatwasit         # add this

        schema "posts" do
          field :title, :string
          field :body, :string
          timestamps
        end

        def changeset(model, params \\ %{}) do
          model
          |> cast(params, ~w(title body)a)
          |> validate_required(~w(title body)a)
          |> prepare_version     # add this
        end
      end

    """
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  embed_template :migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration
    def change do
  <%= @change %>
    end
  end
  """

  #############
  # Config

  defp do_config(opts, bin_opts) do
    base = opts[:module] || (Mix.Project.config() |> Keyword.fetch!(:app) |> to_string |> Macro.camelize())
    opts = Keyword.put(opts, :base, base)
    repo = (opts[:repo] || "#{base}.Repo")

    user_schema = parse_model(opts[:model], base, opts)

    whodoneit = if opts[:whodoneit_map] || opts[:whodoneit_id] || opts[:whodoneit_id_type], do: true, else: opts[:whodoneit]

    case opts[:whodoneit_id_type] do
      false -> :ok
      nil -> :ok
      "uuid" -> :ok
      other ->
        IO.puts "other: #{inspect other}"
        Mix.raise """
        --whodoneit-id-type only supports option uuid
        """
    end

    bin_opts
    |> Enum.map(&({&1, true}))
    |> Enum.into(%{})
    |> Map.put(:base, base)
    |> Map.put(:user_schema, user_schema)
    |> Map.put(:repo, repo)
    |> Map.put(:migration_path, opts[:migration_path])
    |> Map.put(:module, opts[:module])
    |> Map.put(:whodoneit, whodoneit)
    |> Map.put(:whodoneit_id, opts[:whodoneit_id])
    |> Map.put(:whodoneit_map, opts[:whodoneit_map])
    |> Map.put(:whodoneit_id_type, opts[:whodoneit_id_type])
    |> do_default_config(opts)
  end

  defp parse_options(opts) do
    {opts_bin, opts} = Enum.reduce opts, {[], []}, fn
      opt, {acc_bin, acc} ->
        {acc_bin, [opt | acc]}
    end
    opts_bin = Enum.uniq(opts_bin)
    opts_names = Enum.map opts, &(elem(&1, 0))
    with  [] <- Enum.filter(opts_bin, &(&1 not in @switch_names)),
          [] <- Enum.filter(opts_names, &(&1 not in @switch_names)) do
            {opts_bin, opts}
    else
      list -> raise_option_errors(list)
    end
  end

  ################
  # Utilities

  defp pad(i) when i < 10, do: << ?0, ?0 + i >>
  defp pad(i), do: to_string(i)

  defp do_default_config(config, opts) do
    list_to_atoms(@default_booleans)
    |> Enum.reduce(config, fn opt, acc ->
      Map.put acc, opt, Keyword.get(opts, opt, true)
    end)
  end

  defp list_to_atoms(list), do: Enum.map(list, &(String.to_atom(&1)))

  defp parse_model(model, _base, opts) when is_binary(model) do
    case String.split(model, " ", trim: true) do
      [model, table] ->
        {prefix_model(model, opts), String.to_atom(table)}
      [_] ->
        Mix.raise """
        The mix whatwasit.install --model option expects both singular and plural names. For example:

            mix whatwasit.install --model="Account accounts"
        """
    end
  end
  defp parse_model(_, base, _) do
    {"#{base}.User", :users}
  end

  defp prefix_model(model, opts) do
    module = opts[:module] || opts[:base]
    if String.starts_with? model, module do
      model
    else
      module <> "." <>  model
    end
  end

  defp paths do
    [".", :whatwasit]
  end
end
