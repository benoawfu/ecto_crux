defmodule EctoCrux do
  @moduledoc """
  Crud concern to use in helper's schema implementation with common Repo methods.
  You can use crux methods instead of ones generated by `mix phx.gen.schema`.

  ## Installation

  ### add to deps

  ```elixir
  def deps do
    [
      {:ecto_crux, "~> 1.2.4"}
    ]
  end
  ```

  ### configure (in config/config.exs)

  ```elixir
  config :ecto_crux, repo: MyApp.Repo
  ```

  available parameters are:
    * `:repo` - specify repo to use to handle this queryable module
    * `:page_size` [optional] - default page size to use when using pagination if `page_size` is not specified
    * `:order_by` [optional] - default order by expression, will be used in `find_by` and `all`
    * `:select` [optional] - default select expression
    * `:read_only` [optional] - exclude all write functions
    * `:except` [optional] - list of methods to exclude

  ## tl;dr; example

  ```elixir
  defmodule MyApp.Schema.Baguette do
    use Ecto.Schema
    import Ecto.Changeset

    schema "baguettes" do
      field(:name, :string)
      field(:kind, :string)
      field(:type, :string)
      field(:secret, :string)
    end

    def changeset(user, params \\\\ %{}) do
      user
      |> cast(params, [:name, :kind, :type])
      |> validate_required([:name])
    end
  end
  ```

  ```elixir
  defmodule MyApp.Schema.Baguettes do
    use EctoCrux,
      module: MyApp.Schema.Baguette,
      order_by: [asc: :name],
      select: [:name, :kind, :type]

    # tips: this module is also the perfect place to implement
    # all your custom accessors/operations arround this schema
    # that are not covered by ecto_crux.
  end
  ```

  then you could (not exhaustive):
  ```elixir
    alias MyApp.Schema.Baguettes

    # list all baguettes
    baguettes = Baguettes.all()

    # count baguettes
    count = Baguettes.count()

    # create an new baguette
    {:ok, baguette} = Baguettes.create(%{kind: "baguepi"})

    # get a baguette
    baguette = Baguettes.get("01ESRJA5F0MTWH74ZXM9GVW06Y")
    # get a baguette with it's secret
    baguette = Baguettes.get("01ESRJA5F0MTWH74ZXM9GVW06Y",
      select: [:name, :kind, :type, :secret]
    )
    # update it
    {:ok, baguette} = Baguettes.update(baguette, %{kind: "baguepi"})
    # delete it
    Bachette.delete(baguette)


    # find all baguepi baguettes, within Repo prefix "francaise"
    baguettes = Baguettes.find_by(%{kind: "baguepi"}, [prefix: "francaise"])

    # find all baguepi baguettes, within Repo prefix "francaise", that was not soft deleted
    baguettes = Baguettes.find_by(%{kind: "baguepi"}, [prefix: "francaise", exclude_deleted: true])

    # find only baguepi baguettes that was soft deleted
    baguettes = Baguettes.find_by(%{kind: "baguepi"}, [only_deleted: true])

    # find all baguepi baguetes ordered by `kind`, overrides the default `name` ordering
    baguettes = Baguettes.find_by(%{type: "foo"}, [order_by: [asc: :kind]])

    # find all baguepi baguettes, within Repo prefix "francaise" and paginate
    %EctoCrux.Page{} = page = Baguettes.find_by(%{kind: "baguepi"}, [prefix: "francaise", page: 2, page_size: 15])

  ```

  Functions you can now uses with MyApp.Schema.Baguettes are listed [here](EctoCrux.Schema.Baguettes.html#content).

  """

  @doc """
  Checks that a function (atom + arguments count) is not in the list of excluded methods.

  Example:
    excluded?(@except, :create, 2)
  """
  def excluded?(except, method, args), do: args in Keyword.get_values(except, method)

  defmacro __using__(args) do
    quote(bind_quoted: [args: args]) do
      import EctoCrux, only: [excluded?: 3]

      @schema_module args[:module]
      @repo args[:repo] || Application.get_all_env(:ecto_crux)[:repo]
      @page_size args[:page_size] ||
                   Application.get_all_env(:ecto_crux)[:page_size] ||
                   50
      @order_by args[:order_by] || nil
      @select args[:select] || nil
      # allow to not defined functions that are not defined when using Repo with a read_only mode
      @read_only args[:read_only] || false
      # add more here if new "write" functions are added
      @read_only_excepts (@read_only &&
                            [
                              change: 2,
                              create: 2,
                              create_if_not_exist: 1,
                              create_if_not_exist: 2,
                              create_if_not_exist: 3,
                              update: 3,
                              update!: 3,
                              delete: 2
                            ]) || []
      @except (args[:except] || Keyword.new()) |> Keyword.merge(@read_only_excepts)

      ######################################################################################
      # prepared queries
      @init_query @schema_module |> Ecto.Queryable.to_query()

      ######################################################################################

      import Ecto.Query,
        only: [from: 1, from: 2, where: 2, offset: 2, limit: 2, exclude: 2, select: 2]

      alias Ecto.{Query, Queryable}

      @doc "schema module is it associated to"
      def unquote(:schema_module)(), do: @schema_module

      @doc "configured repo to use"
      def unquote(:repo)(), do: @repo

      @doc "default page size if using pagination"
      def unquote(:page_size)(), do: @page_size

      @doc "value of read_only mode"
      def unquote(:read_only)(), do: @read_only

      @doc "value of default order by"
      def unquote(:order_by)(), do: @order_by

      @doc "value of default select"
      def unquote(:select)(), do: @select

      @doc "value of except"
      def unquote(:except)(), do: @except

      @doc "create a new query using schema module"
      # eq: from e in @schema_module
      def init_query(), do: @init_query

      unless excluded?(@except, :change, 2) do
        @doc "call schema_module changeset method"
        def unquote(:change)(blob, attrs \\ %{}), do: @schema_module.changeset(blob, attrs)
      end

      ######################################################################################
      # CREATE ONE

      unless excluded?(@except, :create, 2) do
        @doc """
        [Repo proxy of [insert/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert/2)] Create (insert) a new baguette from attrs

            # Create a new baguette with `:kind` value set to `:tradition`
            {:ok, baguette} = Baguettes.create(%{kind: :tradition})

        ## Options
          @see [Repo.insert/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert/2)

        """
        @spec create(attrs :: map(), opts :: Keyword.t()) ::
                {:ok, @schema_module.t()} | {:error, Ecto.Changeset.t()}
        def unquote(:create)(attrs \\ %{}, opts \\ []) do
          %@schema_module{}
          |> @schema_module.changeset(attrs)
          |> @repo.insert(crux_clean_opts(opts))
        end
      end

      unless excluded?(@except, :create_if_not_exist, 1) do
        @doc """
        Create (insert) a baguette from attrs if it doesn't exist

          # Create a new baguette with `:kind` value set to `:tradition`
          baguette = Baguettes.create(%{kind: :tradition})
          # Create another one with the same kind
          {:ok, another_ baguette} = Baguettes.create_if_not_exist(%{kind: :tradition})
          # `baguette` and `another_baguette` are the same `Baguette`

        ## Options
        @see [Repo.insert/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert/2)
        """
        @spec create_if_not_exist(attrs :: map()) ::
                {:ok, @schema_module.t()} | {:error, Ecto.Changeset.t()}
        def unquote(:create_if_not_exist)(attrs), do: create_if_not_exist(attrs, attrs)
      end

      unless excluded?(@except, :create_if_not_exist, 2) do
        @doc """
        [Repo] Create (insert) a baguette from attrs if it doesn't exist

        Like `create_if_not_exist/1` but you can specify options (like prefix) to give to ecto
        """
        @spec create_if_not_exist(attrs :: map(), opts :: Keyword.t()) ::
                {:ok, @schema_module.t()} | {:error, Ecto.Changeset.t()}
        def unquote(:create_if_not_exist)(attrs, opts) when is_list(opts),
          do: create_if_not_exist(attrs, attrs, opts)

        @doc """
        [Repo] Create (insert) a baguette from attrs if it doesn't exist

        Behave like `create_if_not_exist/1` but you can specify attrs for the presence test, and creation attrs.

        ## Options
        @see [Repo.insert/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert/2)
        """
        @spec create_if_not_exist(presence_attrs :: map(), creation_attrs :: map()) ::
                {:ok, @schema_module.t()} | {:error, Ecto.Changeset.t()}
        def unquote(:create_if_not_exist)(presence_attrs, creation_attrs)
            when is_map(creation_attrs),
            do: create_if_not_exist(presence_attrs, creation_attrs, [])
      end

      unless excluded?(@except, :create_if_not_exist, 3) do
        @doc """
        [Repo] Create (insert) a baguette from attrs if it doesn't exist

        Behave like `create_if_not_exist/1` but you can specify attrs for the presence test, and creation attrs.

        ## Options
        @see [Repo.insert/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert/2)
        """
        @spec create_if_not_exist(
                presence_attrs :: map(),
                creation_attrs :: map(),
                opts :: Keyword.t()
              ) :: {:ok, @schema_module.t()} | {:error, Ecto.Changeset.t()}
        def unquote(:create_if_not_exist)(presence_attrs, creation_attrs, opts)
            when is_map(creation_attrs) and is_list(opts) do
          if exist?(presence_attrs, opts),
            do: {:ok, get_by(presence_attrs, opts)},
            else: create(creation_attrs, opts)
        end
      end

      ######################################################################################
      # UPDATE

      unless excluded?(@except, :update, 3) do
        @doc """
        [Repo proxy] Updates a changeset using its primary key.

            {:ok, updated_baguette} = Baguettes.update(baguette, %{kind: "best"})

        ## Options
          * @see [Repo.update/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:update/2)
        """
        @spec update(blob :: @schema_module.t(), attrs :: map(), opts :: Keyword.t()) ::
                {:ok, @schema_module.t()} | {:error, Ecto.Changeset.t()}
        def unquote(:update)(blob, attrs, opts \\ []) do
          blob
          |> @schema_module.changeset(attrs)
          |> @repo.update(crux_clean_opts(opts))
        end
      end

      unless excluded?(@except, :update!, 3) do
        @doc """
        [Repo proxy] Same as update/2 but return the struct or raises if the changeset is invalid

            updated_baguette = Baguettes.update!(baguette, %{kind: "best"})

        ## Options
          * @see [Repo.update!/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:update!/2)
        """
        @spec update!(blob :: @schema_module.t(), attrs :: map(), opts :: Keyword.t()) ::
                @schema_module.t()
        def unquote(:update!)(blob, attrs, opts \\ []) do
          blob
          |> @schema_module.changeset(attrs)
          |> @repo.update!(crux_clean_opts(opts))
        end
      end

      ######################################################################################
      # DELETE

      unless excluded?(@except, :delete, 2) do
        @doc """
        [Repo proxy] Deletes a struct using its primary key.

          {:ok, deleted_baguette} = Baguettes.delete(baguette)

        ## Options
        * @see [Repo.delete/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:delete/2)
        """
        @spec delete(blob :: @schema_module.t(), opts :: Keyword.t()) ::
                {:ok, @schema_module.t()} | {:error, Ecto.Changeset.t()}
        def unquote(:delete)(blob, opts \\ []), do: @repo.delete(blob, opts)
      end

      # idea: delete all, soft delete using ecto_soft_delete

      ######################################################################################
      # READ ONE

      unless excluded?(@except, :get, 2) do
        @doc """
        [Repo] Fetches a single struct from the data store where the primary key matches the given id.

            # Get the baguette with id primary key `01DACBCR6REMDH6446VCQEZ5EC`
            Baguettes.get("01DACBCR6REMDH6446VCQEZ5EC")
            # Get the baguette with id primary key `01DACBCR6REMDH6446VCQEZ5EC` and preload it's bakery and flavor
            Baguettes.get("01DACBCR6REMDH6446VCQEZ5EC", preloads: [:bakery, :flavor])

        ## Options
          * `preloads` - list of atom to preload
          * `select` - select expression, overrides default select for the crux usage
          * @see [Repo.get/3](https://hexdocs.pm/ecto/Ecto.Repo.html#c:get/3)

        """
        @spec get(id :: term, opts :: Keyword.t()) :: @schema_module.t() | nil
        def unquote(:get)(id, opts \\ []) do
          @schema_module
          |> crux_build_select(Keyword.get(opts, :select, @select))
          |> @repo.get(id, crux_clean_opts(opts))
          |> crux_build_preload(opts[:preloads])
        end
      end

      unless excluded?(@except, :get!, 2) do
        @doc """
        [Repo] Similar to get/2 but raises Ecto.NoResultsError if no record was found.

        ## Options
          * `preloads` - list of atom to preload
          * `select` - select expression, overrides default select for the crux usage
          * @see [Repo.get!/3](https://hexdocs.pm/ecto/Ecto.Repo.html#c:get/3)

        """
        @spec get!(id :: term, opts :: Keyword.t()) :: @schema_module.t()
        def unquote(:get!)(id, opts \\ []) do
          @schema_module
          |> crux_build_select(Keyword.get(opts, :select, @select))
          |> @repo.get!(id, crux_clean_opts(opts))
          |> crux_build_preload(opts[:preloads])
        end
      end

      unless excluded?(@except, :get_by, 2) do
        @doc """
        [Repo] Fetches a single result from the clauses.

            best_baguette = Baguettes.get_by(kind: "best")

        ## Options
          * `preloads` - list of atom to preload
          * `select` - select expression, overrides default select for the crux usage
          * @see [Repo.get_by/3](https://hexdocs.pm/ecto/Ecto.Repo.html#c:get_by/3)
        """
        @spec get_by(clauses :: Keyword.t() | map(), opts :: Keyword.t()) ::
                @schema_module.t() | nil
        def unquote(:get_by)(clauses, opts \\ []) do
          @schema_module
          |> crux_build_select(Keyword.get(opts, :select, @select))
          |> @repo.get_by(clauses, crux_clean_opts(opts))
          |> crux_build_preload(opts[:preloads])
        end
      end

      unless excluded?(@except, :get_by!, 2) do
        @doc """
        [Repo] Similar to get_by/2 but raises Ecto.NoResultsError if no record was found.

        ## Options
          * `preloads` - list of atom to preload
          * `select` - select expression, overrides default select for the crux usage
          * @see [Repo.get_by!/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:get_by!/3)
        """
        @spec get_by!(clauses :: Keyword.t() | map(), opts :: Keyword.t()) ::
                @schema_module.t()
        def unquote(:get_by!)(clauses, opts \\ []) do
          @schema_module
          |> crux_build_select(Keyword.get(opts, :select, @select))
          |> @repo.get_by!(clauses, crux_clean_opts(opts))
          |> crux_build_preload(opts[:preloads])
        end
      end

      ######################################################################################
      # READ MULTI

      unless excluded?(@except, :find_by, 1) do
        @doc """
        [Repo] Fetches all results using the query.
            query = from b in Baguette, where :kind in ["tradition"]
            best_baguettes = Baguettes.find_by(query)
        """
        def unquote(:find_by)(%Ecto.Query{} = query) do
          query
          |> find_by([])
        end
      end

      unless excluded?(@except, :find_by, 2) do
        @doc """
        [Repo] Fetches all results using the query, with opts
            query = from b in Baguette, where :kind in ["tradition"]
            best_baguettes = Baguettes.find_by(query, prefix: "francaise")

        ## Options
          * `order_by` -  order_by expression, overrides default order_by for the crux usage
          * `select` - select expression, overrides default select for the crux usage
          * @see [Repo.all/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:all/2)
        """
        def unquote(:find_by)(%Ecto.Query{} = query, opts) when is_map(opts) do
          query
          |> find_by(to_keyword(opts))
        end

        def unquote(:find_by)(%Ecto.Query{} = query, opts) do
          map_opts = to_map(opts)

          {pagination, query, meta} =
            query
            |> crux_filter_away_delete_if_requested(map_opts)
            |> crux_only_delete_if_requested(map_opts)
            |> crux_paginate(map_opts)

          entries =
            query
            |> crux_build_order_by(Keyword.get(opts, :order_by, @order_by))
            |> crux_build_select(Keyword.get(opts, :select, @select))
            |> @repo.all(crux_clean_opts(opts))
            |> ensure_typed_list()

          case pagination do
            :no_pagination ->
              entries

            :has_pagination ->
              %EctoCrux.Page{
                entries: entries,
                page: meta.page,
                page_size: meta.page_size,
                total_entries: meta.total_entries,
                total_pages: meta.total_pages
              }
          end
        end
      end

      unless excluded?(@except, :find_by, 1) do
        @doc """
        [Repo] Fetches all results from the filter clauses.

            best_baguettes = Baguettes.find_by(kind: "best")
        """
        @spec find_by(filters :: Keyword.t() | map()) :: [@schema_module.t()]

        def unquote(:find_by)(filters) when is_map(filters) do
          filters
          |> to_keyword()
          |> find_by()
        end

        def unquote(:find_by)(filters) when is_list(filters), do: find_by(filters, [])
      end

      unless excluded?(@except, :find_by, 2) do
        @doc """
        [Repo] Fetches all results from the filter clauses, with opts
            best_baguettes = Baguettes.find_by(kind: "best", prefix: "francaise")

        ## Options
          * `order_by` -  order_by expression, overrides default order_by for the crux usage
          * `select` - select expression, overrides default select for the crux usage
          * @see [Repo.all/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:all/2)
        """
        def unquote(:find_by)(filters, opts) when is_list(filters) do
          @init_query
          |> where(^filters)
          |> find_by(opts)
        end

        @spec find_by(filters :: Keyword.t() | map(), opts :: map()) :: [@schema_module.t()]
        def unquote(:find_by)(filters, opts) when is_map(filters) do
          filters
          |> to_keyword()
          |> find_by(opts)
        end
      end

      unless excluded?(@except, :all, 1) do
        @doc """
        [Repo] Fetches all entries from the data store

            # Fetch all Baguettes
            Baguettes.all()
            # Fetch all Baguettes within Repo prefix "francaise"
            Baguettes.all(prefix: "francaise")

        ## Options
          * `order_by` - order_by expression, overrides default order_by for the crux usage
          * `select` - select expression, overrides default select for the crux usage
          * @see [Repo.all/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:all/2)
        """
        @spec all(opts :: Keyword.t()) :: [@schema_module.t()]
        def unquote(:all)(opts \\ []) when is_list(opts), do: find_by(%{}, opts)
      end

      unless excluded?(@except, :stream, 2) do
        @doc """
        Like `find_by/1` by returns a stream to handle large requests

            Repo.transaction(fn ->
              Baguettes.stream(kind: "best")
              |> Stream.chunk_every(@chunk_size)
              |> Stream.each(fn baguettes_chunk ->
                # eat them
              end)
              |> Stream.run()
            end)

        ## Options
          * @see [Repo.stream/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:stream/2)
        """
        @spec stream(filters :: Keyword.t(), opts :: Keyword.t()) :: Enum.t()
        def unquote(:stream)(filters, opts \\ []) do
          map_opts = to_map(opts)

          @schema_module
          |> where(^filters)
          |> crux_filter_away_delete_if_requested(map_opts)
          |> crux_only_delete_if_requested(map_opts)
          |> @repo.stream(crux_clean_opts(opts))
        end
      end

      ######################################################################################
      # SUGAR

      unless excluded?(@except, :preload, 3) do
        @doc """
        [Repo proxy] Preloads all associations on the given struct or structs.

            my_baguette = Baguettes.preload(baguette, [:floor, :boulanger])

        ## Options
          * @see [Repo.preload/2](https://hexdocs.pm/ecto/Ecto.Repo.html#c:preload/3)
        """
        @spec preload(structs_or_struct_or_nil, preloads :: term(), opts :: Keyword.t()) ::
                structs_or_struct_or_nil
              when structs_or_struct_or_nil: [@schema_module.t()] | @schema_module.t() | nil
        def unquote(:preload)(blob, preloads, opts \\ []) do
          blob |> @repo.preload(preloads, opts)
        end
      end

      unless excluded?(@except, :exist?, 2) do
        @doc """
        Test if an entry with <presence_attrs> exists
        """
        @spec exist?(presence_attrs :: map(), opts :: Keyword.t()) :: boolean()
        def unquote(:exist?)(presence_attrs, opts \\ []) do
          presence_attrs = to_keyword(presence_attrs)

          @init_query
          |> where(^presence_attrs)
          |> @repo.exists?(crux_clean_opts(opts))
        end
      end

      unless excluded?(@except, :count, 1) do
        @doc """
        Count number of entries from a query
            query = from b in Baguette, where :kind in ["tradition"]
            baguettes_count = Baguettes.count(query)
        """
        @spec count(query :: Ecto.Query.t()) :: integer()
        def unquote(:count)(%Ecto.Query{} = query) do
          count(query, [])
        end
      end

      unless excluded?(@except, :count, 2) do
        @doc """
        Count number of entries from a query with opts
            query = from b in Baguette, where :kind in ["tradition"]
            baguettes_count = Baguettes.count(query, prefix: "francaise")

        ## Options
          * @see [Repo.aggregate/3](https://hexdocs.pm/ecto/Ecto.Repo.html#c:aggregate/3)
        """
        @spec count(query :: Ecto.Query.t(), opts :: Keyword.t()) :: integer()
        def unquote(:count)(%Ecto.Query{} = query, opts) do
          query
          |> @repo.aggregate(:count, crux_clean_opts(opts))
        end
      end

      unless excluded?(@except, :count, 1) do
        @doc """
        Count number of entries with opts
            baguettes_count = Baguettes.count(prefix: "francaise")

        ## Options
          * @see [Repo.aggregate/3](https://hexdocs.pm/ecto/Ecto.Repo.html#c:aggregate/3)
        """
        @spec count(opts :: Keyword.t()) :: integer()
        def unquote(:count)(opts) when is_list(opts) do
          init_query()
          |> count(opts)
        end
      end

      unless excluded?(@except, :count, 0) do
        @doc """
        Count number of elements
            baguettes_count = Baguettes.count()
        """
        @spec count() :: integer()
        def unquote(:count)() do
          init_query()
          |> count()
        end
      end

      unless excluded?(@except, :count_by, 2) do
        @doc """
        Count number of entries complying with the filter clauses.

        ## Options
          * @see [Repo.aggregate/3](https://hexdocs.pm/ecto/Ecto.Repo.html#c:aggregate/3)
        """
        @spec count_by(filters :: Keyword.t() | map(), opts :: Keyword.t()) :: integer()
        def unquote(:count_by)(filters, opts \\ [])

        def unquote(:count_by)(filters, opts) when is_list(filters) and is_list(opts) do
          @init_query
          |> where(^filters)
          |> count(opts)
        end

        def unquote(:count_by)(filters, opts) when is_map(filters) and is_list(opts) do
          filters
          |> to_keyword()
          |> count_by(opts)
        end
      end

      unless excluded?(@except, :to_schema_atom_params, 2) do
        @doc """
        Create an atom-keyed map from the given map.
        If both a string and an atom keys are provided in the original map, atom key gets priority.

            Baguettes.to_schema_atom_params(%{"kind" => "baguepi", :kind => "tradition", "half?" => true})
            %{kind: "tradition"}

        ## Options
          * `with_assoc` [optional] - add associations fields to the list of allowed fields, defaults to `true`.
        """
        def unquote(:to_schema_atom_params)(mixed_keyed_map, opts \\ [with_assoc: true])
            when is_map(mixed_keyed_map) and is_list(opts) do
          case opts[:with_assoc] do
            true ->
              @schema_module.__schema__(:fields) ++ @schema_module.__schema__(:associations)

            _ ->
              @schema_module.__schema__(:fields)
          end
          |> Enum.reduce(%{}, fn key, atom_keyed_map ->
            string_key = Atom.to_string(key)

            case mixed_keyed_map do
              %{^key => v} -> Map.put(atom_keyed_map, key, v)
              %{^string_key => v} -> Map.put(atom_keyed_map, key, v)
              _ -> atom_keyed_map
            end
          end)
        end
      end

      ######################################################################################
      # PRIVATE

      defp ensure_typed_list(items) do
        case items do
          [%@schema_module{} = _ | _] -> items
          _ -> []
        end
      end

      defp crux_build_preload(blob, nil), do: blob
      defp crux_build_preload(blob, []), do: blob
      defp crux_build_preload(blob, preloads), do: preload(blob, preloads)

      defp crux_build_order_by(blob, nil), do: blob
      defp crux_build_order_by(blob, expr), do: Query.order_by(blob, ^expr)

      defp crux_build_select(blob, nil), do: blob
      defp crux_build_select(blob, expr), do: Query.select(blob, ^expr)

      defp to_keyword(map) when is_map(map), do: map |> Enum.map(fn {k, v} -> {k, v} end)
      defp to_keyword(list) when is_list(list), do: list

      defp to_map(list) when is_list(list), do: list |> Enum.into(%{})
      defp to_map(map) when is_map(map), do: map

      def page_to_offset(page, page_size) when is_integer(page) and is_integer(page_size),
        do: page_size * (page - 1)

      def offset_to_page(offset, page_size) when is_integer(offset) and is_integer(page_size),
        do: (offset / page_size + 1) |> Float.floor() |> round()

      # remove all keys used by crux before being given to Repo
      defp crux_clean_opts(opts) when is_list(opts),
        do:
          Keyword.drop(opts, [
            :exclude_deleted,
            :only_deleted,
            :offset,
            :page,
            :page_size,
            :order_by,
            :select
          ])

      # soft delete (if you use ecto_soft_delete on the field deleted_at)
      defp crux_filter_away_delete_if_requested(
             %Ecto.Query{} = query,
             %{exclude_deleted: true} = opts
           ),
           do: from(e in query, where: is_nil(e.deleted_at))

      defp crux_filter_away_delete_if_requested(%Ecto.Query{} = query, %{} = opts), do: query

      defp crux_only_delete_if_requested(%Ecto.Query{} = query, %{only_deleted: true} = opts),
        do: from(e in query, where: not is_nil(e.deleted_at))

      defp crux_only_delete_if_requested(%Ecto.Query{} = query, %{} = opts), do: query

      # pagination
      defp crux_paginate(%Ecto.Query{} = query, %{page: page} = opts)
           when is_integer(page) and page > 0 do
        page_size = crux_page_size(opts)
        total_entries = count(query, to_keyword(opts))
        total_pages = crux_total_pages(total_entries, page_size)
        page = min(page, total_pages)

        meta = %{
          page_size: page_size,
          total_entries: total_entries,
          total_pages: total_pages,
          page: page
        }

        do_crux_paginate(query, page_to_offset(page, page_size), meta)
      end

      defp crux_paginate(%Ecto.Query{} = query, %{offset: offset} = opts)
           when is_integer(offset) and offset >= 0 do
        page_size = crux_page_size(opts)
        total_entries = count(query, to_keyword(opts))
        offset = min(offset, total_entries)

        meta = %{
          page_size: page_size,
          total_entries: total_entries,
          total_pages: crux_total_pages(total_entries, page_size),
          page: offset_to_page(offset, page_size)
        }

        do_crux_paginate(query, offset, meta)
      end

      defp crux_paginate(%Ecto.Query{} = query, %{} = _opts), do: {:no_pagination, query, nil}

      defp do_crux_paginate(
             %Ecto.Query{} = query,
             offset,
             %{page_size: page_size, total_entries: _, total_pages: _, page: _} = meta
           ) do
        query =
          query
          |> offset(^offset)
          |> limit(^page_size)

        {:has_pagination, query, meta}
      end

      defp crux_page_size(opts) when is_map(opts), do: Map.get(opts, :page_size, @page_size)

      defp crux_total_pages(0, _), do: 1

      defp crux_total_pages(total_entries, page_size) do
        (total_entries / page_size) |> Float.ceil() |> round()
      end
    end
  end
end
