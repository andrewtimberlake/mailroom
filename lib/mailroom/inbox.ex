defmodule Mailroom.Inbox do
  alias Mailroom.IMAP.{Envelope, BodyStructure}
  require Logger

  defmodule Match do
    defstruct patterns: [], module: nil, function: nil
  end

  defmodule State do
    defstruct opts: [], client: nil, assigns: %{}
  end

  defmodule MessageContext do
    defstruct id: nil,
              type: :imap,
              envelope: nil,
              client: nil,
              assigns: %{}
  end

  defp supports_continue? do
    case Integer.parse(to_string(:erlang.system_info(:otp_release))) do
      {version, _} -> version >= 21
      _ -> false
    end
  end

  defmacro __using__(opts \\ []) do
    default_opts = [use_continue: supports_continue?()]
    opts = Keyword.merge(default_opts, opts)

    quote location: :keep do
      require Mailroom.Inbox
      import Mailroom.Inbox
      require Logger
      use GenServer

      alias Mailroom.IMAP

      @matches []
      @before_compile unquote(__MODULE__)

      def init(args) do
        opts = __MODULE__.config(args)

        state = %State{opts: opts, assigns: Keyword.get(opts, :assigns, %{})}

        if Keyword.get(unquote(opts), :use_continue) do
          {:ok, state, {:continue, :after_init}}
        else
          send(self(), :after_init)
          {:ok, state}
        end
      end

      def config(opts), do: opts

      def start_link(args) do
        GenServer.start_link(__MODULE__, args)
      end

      def close(pid), do: GenServer.call(pid, :close)

      def handle_call(:close, _from, %{client: client} = state) do
        IMAP.cancel_idle(client)
        IMAP.logout(client)
        {:reply, :ok, %{state | client: nil}}
      end

      def handle_info(:after_init, state) do
        # IO.puts("handle_info(:after_init, #{inspect(state)})")
        handle_continue(:after_init, state)
      end

      def handle_info(:idle_notify, %{client: client} = state) do
        if client, do: process_mailbox(client, state)
        {:noreply, state}
      end

      def handle_info(msg, state) do
        IO.warn(msg, label: "handle_info")
        {:noreply, state}
      end

      def handle_continue(:after_init, %{opts: opts} = state) do
        # IO.puts("handle_continue(:after_init, #{inspect(state)})")

        server = Keyword.get(opts, :server)

        {:ok, client} =
          IMAP.connect(
            server,
            Keyword.get(opts, :username),
            Keyword.get(opts, :password),
            opts
          )

        folder = Keyword.get(opts, :folder, :inbox)
        Logger.info("Connecting to #{folder} on #{server}")
        IMAP.select(client, folder)
        process_mailbox(client, state)

        {:noreply, %{state | client: client}}
      end

      defp idle(client) do
        IMAP.idle(client, self(), :idle_notify)
      end

      defoverridable config: 1
    end
  end

  defmacro match(patterns, module \\ nil, function) do
    patterns = Macro.escape(patterns)

    quote do
      @matches [
        %Match{patterns: unquote(patterns), module: unquote(module), function: unquote(function)}
        | @matches
      ]
    end
  end

  # All the Enum.reverse statements ensure that the functions generated follow the order of the match statements and the defined patterns
  defmacro __before_compile__(env) do
    matches = Module.get_attribute(env.module, :matches)

    match_keys = get_match_keys(matches)
    match_functions = build_match_functions(matches)

    conditions = build_condition_clauses(matches)

    response_keys = [envelope: {:envelope, [], Elixir}]

    response_keys =
      if :has_attachment in match_keys,
        do: Keyword.put(response_keys, :body_structure, {:body_structure, [], Elixir}),
        else: response_keys

    match_argument = {:%{}, [], response_keys}

    normalize =
      {:=, [],
       [
         {:envelope, [], Elixir},
         {{:., [], [{:__aliases__, [alias: false], [Envelope]}, :normalize]}, [],
          [{:envelope, [], Elixir}]}
       ]}

    fetch_keys = Keyword.keys(response_keys)

    main_func =
      quote location: :keep do
        defp process_mailbox(client, %{assigns: assigns}) do
          emails = Mailroom.IMAP.email_count(client)
          Logger.info("Processing #{emails} emails")

          if emails > 0 do
            Mailroom.IMAP.each(client, unquote(fetch_keys), fn {msg_id, response} ->
              # IO.inspect(response, label: "response")

              case perform_match(client, msg_id, response, assigns) do
                :done ->
                  Mailroom.IMAP.add_flags(client, msg_id, [:deleted])

                :no_match ->
                  Mailroom.IMAP.add_flags(client, msg_id, [:seen])
              end
            end)

            Mailroom.IMAP.expunge(client)
          end

          Logger.info("Entering IDLE")
          idle(client)
        end

        def match(unquote(match_argument)) do
          unquote(normalize)
          cond do: unquote(conditions)
        end

        def perform_match(client, msg_id, response, assigns \\ %{}) do
          {result, mod_fun} =
            case match(response) do
              :no_match ->
                {:no_match, nil}

              {module, function} ->
                context = %MessageContext{
                  id: msg_id,
                  envelope: response[:envelope],
                  client: client,
                  assigns: assigns
                }

                # Logger.debug("  match: #{module || __MODULE__}##{function}")
                mod = module || __MODULE__

                {apply(mod, function, [context]), {mod, function}}
            end

          Logger.info(fn ->
            %{envelope: %{to: to, from: from, subject: subject}} = response

            "Processing msg:#{msg_id} TO:#{log_email(to)} FROM:#{log_email(from)} SUBJECT:#{inspect(subject)} using #{log_mod_fun(mod_fun)} -> #{inspect(result)}"
          end)

          result
        end

        defp log_email([]), do: "Unknown"
        defp log_email([%{email: email} | _]), do: email

        defp log_mod_fun(nil), do: ""
        defp log_mod_fun({mod, fun}), do: "#{inspect(mod)}##{fun}"
      end

    [main_func | match_functions]
    # |> print_macro
  end

  defp get_match_keys(matches) do
    matches
    |> Enum.flat_map(fn %Match{patterns: patterns} ->
      Enum.map(patterns, fn {field, _} -> field end)
    end)
    |> Enum.uniq()
  end

  defp build_match_functions(matches) do
    matches
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce([], fn {%Match{patterns: patterns}, index}, acc ->
      patterns
      |> merge_duplicate_patterns
      |> Enum.to_list()
      |> Enum.reverse()
      |> Enum.reduce(acc, fn
        {field, patterns}, acc when is_list(patterns) ->
          match_functions =
            patterns
            |> Enum.reduce(acc, fn pattern, acc ->
              [create_match_function(index, field, pattern) | acc]
            end)
            |> Enum.reverse()

          [create_match_failure_function(index, field, hd(patterns)) | match_functions]

        {field, pattern}, acc ->
          [
            create_match_failure_function(index, field, pattern),
            create_match_function(index, field, pattern) | acc
          ]
      end)
    end)
    |> Enum.reverse()

    # |> print_macro
  end

  defp build_condition_clauses(matches) do
    conditions =
      matches
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.flat_map(fn {%Match{patterns: patterns, module: module, function: function}, index} ->
        keys = patterns |> Keyword.keys() |> Enum.uniq()
        conditions = build_conditions(index, keys)
        # |> print_macro
        quote do: (unquote(conditions) -> {unquote(module), unquote(function)})
      end)

    fallback_condition = quote do: (true -> :no_match)
    conditions ++ fallback_condition
  end

  defp build_conditions(index, fields, acc \\ [])
  defp build_conditions(_index, [], [condition]), do: condition

  defp build_conditions(_index, [], acc),
    do: {{:., [], [{:__aliases__, [alias: false], [Enum]}, :all?]}, [], [Enum.reverse(acc)]}

  ~w[to cc bcc from sender]a
  |> Enum.each(fn field ->
    defp build_conditions(index, [unquote(field) | fields], acc) do
      accessor = {{:., [], [{:envelope, [], Elixir}, unquote(field)]}, [], []}

      function =
        {:&, [],
         [
           {:/, [context: Elixir, import: Kernel],
            [{:"matches_#{index}_#{unquote(field)}", [], Elixir}, 1]}
         ]}

      condition = quote do: Enum.any?(List.wrap(unquote(accessor)), unquote(function))
      build_conditions(index, fields, [condition | acc])
    end
  end)

  defp build_conditions(index, [:has_attachment | fields], acc) do
    function =
      {{:., [], [{:__aliases__, [alias: false], [BodyStructure]}, :has_attachment?]}, [],
       [{:body_structure, [], Elixir}]}

    build_conditions(index, fields, [function | acc])
  end

  defp build_conditions(index, [field | fields], acc) do
    accessor = {{:., [], [{:envelope, [], Elixir}, field]}, [], []}
    function = {:"matches_#{index}_#{field}", [], [accessor]}
    build_conditions(index, fields, [function | acc])
  end

  defp merge_duplicate_patterns(patterns) do
    patterns
    |> Enum.reduce(%{}, fn {key, value}, map ->
      Map.update(map, key, value, &[value | List.wrap(&1)])
    end)
  end

  defp create_match_function(index, field, {:sigil_r, _, _} = regex) do
    quote do
      defp unquote(:"matches_#{index}_#{field}")(nil), do: false

      defp unquote(:"matches_#{index}_#{field}")(string) do
        Regex.match?(unquote(regex), string)
      end
    end
  end

  defp create_match_function(index, field, string) when is_binary(string) do
    quote do
      defp unquote(:"matches_#{index}_#{field}")(<<unquote(string), _rest::binary>>), do: true
      defp unquote(:"matches_#{index}_#{field}")(_), do: false
    end
  end

  defp create_match_function(index, field, pattern) do
    quote do
      defp unquote(:"matches_#{index}_#{field}")(unquote(pattern)) do
        true
      end
    end
  end

  defp create_match_failure_function(_index, _field, {:sigil_r, _, _}), do: nil
  defp create_match_failure_function(_index, _field, string) when is_binary(string), do: nil

  defp create_match_failure_function(index, field, _pattern) do
    quote do
      defp unquote(:"matches_#{index}_#{field}")(_), do: false
    end
  end

  # defp print_macro(quoted) do
  #   quoted |> Macro.to_string() |> IO.puts()
  #   quoted
  # end
end
