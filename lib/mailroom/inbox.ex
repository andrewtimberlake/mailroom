defmodule Mailroom.Inbox do
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
              mail_info: nil,
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
      import Mailroom.Inbox.MatchUtils

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

  defmacro match(do: match_block) do
    matches =
      case match_block do
        {:__block__, _, matches} -> matches
        {:process, _, _} = process -> [process]
        item -> [item]
      end

    {process, matches} =
      case Enum.reverse(matches) do
        [{:process, _, _} = process | matches] -> {process, Enum.reverse(matches)}
        _ -> raise("A match block must have a call to process")
      end

    {module, function} =
      case process do
        {:process, _, [module, function]} -> {module, function}
        {:process, _, [function]} -> {nil, function}
      end

    quote do
      @matches [
        %Match{
          patterns: unquote(Macro.escape(matches)),
          module: unquote(module),
          function: unquote(function)
        }
        | @matches
      ]
    end
  end

  defmacro __before_compile__(env) do
    matches =
      Module.get_attribute(env.module, :matches)
      |> Enum.reverse()
      |> Enum.map(fn %{patterns: patterns, module: module, function: function} ->
        patterns =
          Enum.map(patterns, fn {func_name, context, arguments} ->
            {:&, [], [{:"match_#{func_name}", context, [{:&, [], [1]} | List.wrap(arguments)]}]}
          end)

        {:{}, [], [patterns, module, function]}
      end)

    quote location: :keep do
      defp process_mailbox(client, %{assigns: assigns}) do
        emails = Mailroom.IMAP.email_count(client)

        if emails > 0 do
          Logger.debug("Processing #{emails} emails")

          Mailroom.IMAP.each(client, [:envelope, :body_structure], fn {msg_id, response} ->
            %{envelope: envelope, body_structure: body_structure} = response
            mail_info = generate_mail_info(envelope, body_structure)

            case perform_match(client, msg_id, mail_info, assigns) do
              :done ->
                Mailroom.IMAP.add_flags(client, msg_id, [:deleted])

              :no_match ->
                Mailroom.IMAP.add_flags(client, msg_id, [:seen])
            end
          end)

          Mailroom.IMAP.expunge(client)
        end

        Logger.debug("Entering IDLE")
        idle(client)
      end

      def do_match(mail_info) do
        match =
          unquote(matches)
          |> Enum.find(fn {patterns, _, _} ->
            Enum.all?(patterns, & &1.(mail_info))
          end)

        case match do
          nil ->
            :no_match

          {_, module, function} ->
            {module, function}
        end

        # unquote(normalize)
        # cond do: unquote(conditions)
      end

      def perform_match(client, msg_id, mail_info, assigns \\ %{}) do
        {result, mod_fun} =
          case do_match(mail_info) do
            :no_match ->
              {:no_match, nil}

            {module, function} ->
              context = %MessageContext{
                id: msg_id,
                mail_info: mail_info,
                client: client,
                assigns: assigns
              }

              # Logger.debug("  match: #{module || __MODULE__}##{function}")
              mod = module || __MODULE__

              {apply(mod, function, [context]), {mod, function}}
          end

        Logger.info(fn ->
          %{to: to, from: from, subject: subject} = mail_info

          "Processing msg:#{msg_id} TO:#{log_email(to)} FROM:#{log_email(from)} SUBJECT:#{
            inspect(subject)
          } using #{log_mod_fun(mod_fun)} -> #{inspect(result)}"
        end)

        result
      end

      defp log_email([]), do: "Unknown"
      defp log_email([email | _]), do: email

      defp log_mod_fun(nil), do: ""
      defp log_mod_fun({mod, fun}), do: "#{inspect(mod)}##{fun}"
    end

    # |> print_macro
  end

  # defp print_macro(quoted) do
  #   quoted |> Macro.to_string() |> IO.puts()
  #   quoted
  # end
end
