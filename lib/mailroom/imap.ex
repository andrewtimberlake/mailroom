defmodule Mailroom.IMAP do
  require Logger
  use GenServer

  import Mailroom.IMAP.Utils
  alias Mailroom.IMAP.{Envelope, BodyStructure}
  alias Mailroom.Socket

  defmodule State do
    @moduledoc false

    @type mailbox :: {String.t() | atom, :r | :rw}
    @type connection :: :unauthenticated | :authenticated | :logged_out | :selected

    @type t :: %__MODULE__{
            socket: Socket.t() | nil,
            state: connection,
            ssl: boolean,
            debug: boolean,
            cmd_map: map,
            cmd_number: non_neg_integer,
            capability: [String.t()] | nil,
            flags: iolist,
            permanent_flags: iolist,
            uid_validity: non_neg_integer | nil,
            uid_next: non_neg_integer | nil,
            unseen: non_neg_integer,
            highest_mod_seq: non_neg_integer | nil,
            recent: integer,
            exists: integer,
            temp: any,
            mailbox: mailbox | nil,
            idle_caller: GenServer.from() | nil,
            idle_reply_msg: any,
            idle_timer: reference | nil
          }

    defstruct socket: nil,
              state: :unauthenticated,
              ssl: false,
              debug: false,
              cmd_map: %{},
              cmd_number: 1,
              capability: [],
              flags: [],
              permanent_flags: [],
              uid_validity: nil,
              uid_next: nil,
              unseen: 0,
              highest_mod_seq: nil,
              recent: 0,
              exists: 0,
              temp: nil,
              mailbox: nil,
              idle_caller: nil,
              idle_reply_msg: nil,
              idle_timer: nil
  end

  @moduledoc """
  Handles communication with a IMAP server.

  ## Example:

      {:ok, client} = #{inspect(__MODULE__)}.connect("imap.server", "username", "password")
      client
      |> #{inspect(__MODULE__)}.list
      |> Enum.each(fn(mail) ->
        message =
          client
          |> #{inspect(__MODULE__)}.retrieve(mail)
          |> Enum.join("\\n")
        # … process message
        #{inspect(__MODULE__)}.delete(client, mail)
      end)
      #{inspect(__MODULE__)}.reset(client)
      #{inspect(__MODULE__)}.close(client)
  """

  @doc """
  Connect to the IMAP server

  The following options are available:

    - `ssl` - default `false`, connect via SSL or not
    - `port` - default `110` (`995` if SSL), the port to connect to
    - `timeout` - default `15_000`, the timeout for connection and communication

  ## Examples:

      #{inspect(__MODULE__)}.connect("imap.server", "me", "secret", ssl: true)
      {:ok, pid}
  """
  def connect(server, username, password, options \\ []) do
    opts = parse_opts(options)
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    GenServer.call(pid, {:connect, server, opts.port})

    case login(pid, username, password) do
      {:ok, _msg} -> {:ok, pid}
      {:error, reason} -> {:error, :authentication, reason}
    end
  end

  defp parse_opts(opts, acc \\ %{ssl: false, port: nil, debug: false})

  defp parse_opts([], acc),
    do: set_default_port(acc)

  defp parse_opts([{:ssl, ssl} | tail], acc),
    do: parse_opts(tail, Map.put(acc, :ssl, ssl))

  defp parse_opts([{:port, port} | tail], acc),
    do: parse_opts(tail, Map.put(acc, :port, port))

  defp parse_opts([{:debug, debug} | tail], acc),
    do: parse_opts(tail, Map.put(acc, :debug, debug))

  defp parse_opts([_ | tail], acc),
    do: parse_opts(tail, acc)

  defp set_default_port(%{port: nil, ssl: false} = opts),
    do: %{opts | port: 143}

  defp set_default_port(%{port: nil, ssl: true} = opts),
    do: %{opts | port: 993}

  defp set_default_port(opts),
    do: opts

  defp login(pid, username, password),
    do: GenServer.call(pid, {:login, username, password})

  def select(pid, mailbox_name),
    do: GenServer.call(pid, {:select, mailbox_name}) && pid

  def examine(pid, mailbox_name),
    do: GenServer.call(pid, {:examine, mailbox_name}) && pid

  def list(pid, reference \\ "", mailbox_name \\ "*"),
    do: GenServer.call(pid, {:list, reference, mailbox_name})

  def status(pid, mailbox_name, items),
    do: GenServer.call(pid, {:status, mailbox_name, items})

  @doc ~S"""
  Fetches the items for the specified message or range of messages

  ## Examples:

      > IMAP.fetch(client, 1, [:uid])
      #…
      > IMAP.fetch(client, 1..3, [:fast, :uid])
      #…
  """
  def fetch(pid, number_or_range, items_list, func \\ nil, opts \\ []) do
    {:ok, list} =
      GenServer.call(
        pid,
        {:fetch, number_or_range, items_list},
        Keyword.get(opts, :timeout, 300_000)
      )

    if func do
      Enum.each(list, func)
      pid
    else
      {:ok, list}
    end
  end

  def uid_fetch(pid, number_or_range, items_list, opts \\ []) do
    GenServer.call(
      pid,
      {:uid_fetch, number_or_range, items_list},
      Keyword.get(opts, :timeout, 300_000)
    )
  end

  def search(pid, query, items_list \\ nil, func \\ nil) do
    {:ok, list} = GenServer.call(pid, {:search, query}, 60_000)

    if func do
      list
      |> numbers_to_sequences
      |> Enum.each(fn number_or_range ->
        {:ok, list} = fetch(pid, number_or_range, items_list)
        Enum.each(list, func)
      end)

      pid
    else
      {:ok, list}
    end
  end

  def uid_search(pid, query) do
    GenServer.call(pid, {:uid_search, query}, 60_000)
  end

  def each(pid, items_list \\ [:envelope], func) do
    pid
    |> email_count
    |> split_into_ranges(100)
    |> Enum.each(fn range ->
      fetch(pid, range, items_list, fn {msg_id, response} ->
        func.({msg_id, response})
      end)
    end)

    pid
  end

  defp split_into_ranges(0, _chunks), do: []
  defp split_into_ranges(length, chunks, start \\ 0)

  defp split_into_ranges(length, chunks, start) when start + chunks < length do
    [(start + 1)..(start + chunks) | split_into_ranges(length, chunks, start + chunks)]
  end

  defp split_into_ranges(length, _chunks, start) do
    [(start + 1)..length]
  end

  def remove_flags(pid, number_or_range, flags, opts \\ []),
    do: GenServer.call(pid, {:remove_flags, number_or_range, flags, opts}) && pid

  def add_flags(pid, number_or_range, flags, opts \\ []),
    do: GenServer.call(pid, {:add_flags, number_or_range, flags, opts}) && pid

  def set_flags(pid, number_or_range, flags, opts \\ []),
    do: GenServer.call(pid, {:set_flags, number_or_range, flags, opts}) && pid

  def copy(pid, sequence, mailbox_name),
    do: GenServer.call(pid, {:copy, sequence, mailbox_name}) && pid

  def expunge(pid),
    do: GenServer.call(pid, :expunge) && pid

  @doc ~S"""
  ## Options
   - `:timeout` - (integer) number of milliseconds before terminating the idle command if no update has been received. Defaults to `1_500_00` (25 minutes)
  """
  def idle(pid, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1_500_000)
    GenServer.call(pid, {:idle, timeout}, :infinity) && pid
  end

  def idle(pid, callback_pid, callback_message, opts \\ []) when is_pid(callback_pid) do
    timeout = Keyword.get(opts, :timeout, 1_500_000)
    GenServer.cast(pid, {:idle, timeout, callback_pid, callback_message}) && pid
  end

  def cancel_idle(pid) do
    GenServer.call(pid, :cancel_idle) && pid
  end

  def close(pid),
    do: GenServer.call(pid, :close) && pid

  def logout(pid),
    do: GenServer.call(pid, :logout) && pid

  def email_count(pid),
    do: GenServer.call(pid, :email_count)

  def recent_count(pid),
    do: GenServer.call(pid, :recent_count)

  def unseen_count(pid),
    do: GenServer.call(pid, :unseen_count)

  def mailbox(pid),
    do: GenServer.call(pid, :mailbox)

  def state(pid),
    do: GenServer.call(pid, :state)

  def init(opts) do
    {:ok, %{debug: opts.debug, ssl: opts.ssl}}
  end

  def handle_call({:connect, server, port}, from, state) do
    {:ok, socket} = Socket.connect(server, port, ssl: state.ssl, debug: state.debug, active: true)

    {:noreply,
     %State{
       socket: socket,
       state: :unauthenticated,
       debug: state.debug,
       ssl: state.ssl,
       cmd_map: %{connect: from}
     }}
  end

  def handle_call({:login, username, password}, from, %{capability: capability} = state) do
    if Enum.member?(capability, "STARTTLS") do
      {:noreply,
       send_command(from, "STARTTLS", %{state | temp: %{username: username, password: password}})}
    else
      {:noreply,
       send_command(
         from,
         ["LOGIN", " ", quote_string(username), " ", quote_string(password)],
         state
       )}
    end
  end

  def handle_call({:select, :inbox}, from, state),
    do: handle_call({:select, "INBOX"}, from, state)

  def handle_call({:select, mailbox}, from, state),
    do: {:noreply, send_command(from, ["SELECT", " ", mailbox], %{state | temp: mailbox})}

  def handle_call({:examine, :inbox}, from, state),
    do: handle_call({:examine, "INBOX"}, from, state)

  def handle_call({:examine, mailbox}, from, state),
    do: {:noreply, send_command(from, ["EXAMINE", " ", mailbox], %{state | temp: mailbox})}

  def handle_call({:list, reference, mailbox_name}, from, state) do
    {:noreply,
     send_command(
       from,
       ["LIST", " ", quote_string(reference), " ", quote_string(mailbox_name)],
       state
     )}
  end

  def handle_call({:status, mailbox_name, items}, from, state) do
    {:noreply,
     send_command(
       from,
       ["STATUS", " ", quote_string(mailbox_name), " ", items_to_list(items)],
       state
     )}
  end

  def handle_call({:fetch, sequence, items}, from, state) do
    {:noreply,
     send_command(from, ["FETCH", " ", to_sequence(sequence), " ", items_to_list(items)], %{
       state
       | temp: []
     })}
  end

  def handle_call({:uid_fetch, sequence, items}, from, state) do
    {:noreply,
     send_command(from, ["UID FETCH", " ", to_sequence(sequence), " ", items_to_list(items)], %{
       state
       | temp: []
     })}
  end

  def handle_call({:search, query}, from, state),
    do: {:noreply, send_command(from, ["SEARCH", " ", query], %{state | temp: []})}

  def handle_call({:uid_search, query}, from, state),
    do: {:noreply, send_command(from, ["UID SEARCH", " ", query], %{state | temp: []})}

  [remove_flags: "-FLAGS", add_flags: "+FLAGS", set_flags: "FLAGS"]
  |> Enum.each(fn {func_name, command} ->
    def handle_call({unquote(func_name), sequence, flags, opts}, from, state) do
      {:noreply,
       send_command(
         from,
         [
           "STORE",
           " ",
           to_sequence(sequence),
           " ",
           unquote(command),
           store_silent(opts),
           " ",
           flags_to_list(flags)
         ],
         %{state | temp: []}
       )}
    end
  end)

  def handle_call({:copy, sequence, mailbox_name}, from, state) do
    {:noreply,
     send_command(
       from,
       ["COPY", " ", to_sequence(sequence), " ", quote_string(mailbox_name)],
       state
     )}
  end

  def handle_call(:expunge, from, state),
    do: {:noreply, send_command(from, "EXPUNGE", state)}

  def handle_call({:idle, timeout}, from, state) do
    timer = Process.send_after(self(), :idle_timeout, timeout)
    {:noreply, send_command(from, "IDLE", %{state | idle_caller: from, idle_timer: timer})}
  end

  def handle_call(
        :cancel_idle,
        _from,
        %{socket: socket, idle_caller: caller, idle_timer: timer} = state
      ) do
    if caller do
      cancel_idle(socket, timer)
    end

    {:reply, :ok, state}
  end

  def handle_call(:close, from, state),
    do: {:noreply, send_command(from, "CLOSE", state)}

  def handle_call(:logout, from, state),
    do: {:noreply, send_command(from, "LOGOUT", state)}

  def handle_call(:email_count, _from, %{exists: exists} = state),
    do: {:reply, exists, state}

  def handle_call(:recent_count, _from, %{recent: recent} = state),
    do: {:reply, recent, state}

  def handle_call(:unseen_count, _from, %{unseen: unseen} = state),
    do: {:reply, unseen, state}

  def handle_call(:mailbox, _from, %{mailbox: mailbox} = state),
    do: {:reply, mailbox, state}

  def handle_call(:state, _from, %{state: connection_state} = state),
    do: {:reply, connection_state, state}

  def handle_cast({:idle, timeout, reply_to, reply_with}, state) do
    timer = Process.send_after(self(), :idle_timeout, timeout)

    {:noreply,
     send_command(nil, "IDLE", %{
       state
       | idle_caller: reply_to,
         idle_reply_msg: reply_with,
         idle_timer: timer
     })}
  end

  def handle_info({:ssl, _socket, msg}, state) do
    if state.debug, do: IO.write(["> [ssl] ", msg])
    handle_response(msg, state)
  end

  def handle_info({:tcp, _socket, msg}, state) do
    if state.debug, do: IO.write(["> [tcp] ", msg])
    handle_response(msg, state)
  end

  def handle_info(:idle_timeout, %{socket: socket} = state) do
    cancel_idle(socket, nil)
    {:noreply, state}
  end

  def handle_info({:ssl_closed, _}, state) do
    Logger.warn("SSL closed")
    {:stop, :ssl_closed, state}
  end

  defp cancel_idle(socket, timer) do
    if timer, do: Process.cancel_timer(timer)
    :ok = Socket.send(socket, ["DONE\r\n"])
  end

  defp handle_response(
         <<"* OK ", msg::binary>>,
         %{state: :unauthenticated, cmd_map: %{connect: caller} = cmd_map} = state
       ) do
    state = process_connection_message(msg, state)
    GenServer.reply(caller, {:ok, msg})
    {:noreply, %{state | cmd_map: Map.delete(cmd_map, :connect)}}
  end

  defp handle_response(<<"* OK [PERMANENTFLAGS ", msg::binary>>, state),
    do: {:noreply, %{state | permanent_flags: parse_list_only(msg)}}

  defp handle_response(<<"* OK [UIDVALIDITY ", msg::binary>>, state),
    do: {:noreply, %{state | uid_validity: parse_number(msg)}}

  defp handle_response(<<"* OK [UNSEEN ", msg::binary>>, state),
    do: {:noreply, %{state | unseen: parse_number(msg)}}

  defp handle_response(<<"* OK [UIDNEXT ", msg::binary>>, state),
    do: {:noreply, %{state | uid_next: parse_number(msg)}}

  defp handle_response(<<"* OK [HIGHESTMODSEQ ", msg::binary>>, state),
    do: {:noreply, %{state | highest_mod_seq: parse_number(msg)}}

  defp handle_response(<<"* OK [CAPABILITY ", msg::binary>>, state) do
    {:noreply, %{state | capability: parse_capability(msg)}}
  end

  defp handle_response(<<"* CAPABILITY ", msg::binary>>, state),
    do: {:noreply, %{state | capability: parse_capability(msg)}}

  defp handle_response(<<"* LIST ", rest::binary>>, %{temp: temp} = state) do
    {flags, <<" ", rest::binary>>} = parse_list(rest)
    {delimiter, <<" ", rest::binary>>} = parse_string(rest)
    mailbox = parse_string_only(rest)
    {:noreply, %{state | temp: [{mailbox, delimiter, flags} | List.wrap(temp)]}}
  end

  defp handle_response(<<"* STATUS ", rest::binary>>, state) do
    {_mailbox, <<rest::binary>>} = parse_string(rest)
    response = parse_list_only(rest)
    response = list_to_status_items(response)
    {:noreply, %{state | temp: response}}
  end

  defp handle_response(<<"* FLAGS ", msg::binary>>, state),
    do: {:noreply, %{state | flags: parse_list_only(msg)}}

  defp handle_response(<<"* SEARCH ", msg::binary>>, state) do
    sequence_numbers =
      msg
      |> trim()
      |> String.split(" ")
      |> Enum.map(&String.to_integer/1)

    {:noreply, %{state | temp: sequence_numbers}}
  end

  defp handle_response(<<"* SEARCH", _msg::binary>>, state),
    do: {:noreply, state}

  defp handle_response(<<"* BYE ", _msg::binary>>, state),
    do: {:noreply, state}

  defp handle_response(<<"* ", msg::binary>>, state) do
    case String.split(msg, " ", parts: 3) do
      [number, "EXISTS\r\n"] ->
        handle_exists(String.to_integer(number), state)

      [number, "RECENT\r\n"] ->
        {:noreply, %{state | recent: String.to_integer(number)}}

      [_number, "EXPUNGE\r\n"] ->
        {:noreply, %{state | exists: state.exists - 1}}

      [number, "FETCH", rest] ->
        data = process_fetch_data(rest, state)

        {:noreply,
         %{state | temp: [{String.to_integer(number), parse_fetch_response(data)} | state.temp]}}

      _ ->
        Logger.warn("Unknown untagged response: #{msg}")
        {:noreply, state}
    end
  end

  defp handle_response(<<"+ idling", _rest::binary>>, state),
    do: {:noreply, state}

  defp handle_response(<<cmd_tag::binary-size(4), " ", msg::binary>>, state),
    do: handle_tagged_response(cmd_tag, msg, state)

  defp handle_response(msg, state) do
    Logger.warn("handle_response(socket, #{inspect(msg)}, #{inspect(state)})")
    {:noreply, state}
  end

  defp process_fetch_data(data, state) do
    case Regex.run(~r/\A(.+ {(\d+)}\r\n)\z/sm, data) do
      [_, initial, bytes] ->
        data = fetch_all_data(String.to_integer(bytes), 0, [initial], state)
        process_fetch_data(data, state)

      _ ->
        data
    end
  end

  defp handle_exists(number, %{socket: socket, idle_caller: caller, idle_timer: timer} = state) do
    if caller do
      cancel_idle(socket, timer)
    end

    {:noreply, %{state | exists: number}}
  end

  defp parse_fetch_response(string) do
    string
    |> parse_list_only
    |> list_to_items
    |> parse_fetch_results
  end

  defp parse_fetch_results(%{} = map) do
    map
    |> Enum.map(fn {key, value} ->
      try do
        parse_fetch_item(key, value)
      rescue
        _ ->
          {key, :error}
      end
    end)
    |> Map.new()
  end

  defp parse_fetch_item(:internal_date, datetime),
    do: {:internal_date, parse_timestamp(datetime)}

  defp parse_fetch_item(:uid, datetime),
    do: {:uid, parse_number(datetime)}

  defp parse_fetch_item(:envelope, envelope),
    do: {:envelope, Envelope.new(envelope)}

  defp parse_fetch_item(:body_structure, body_structure),
    do: {:body_structure, BodyStructure.new(body_structure)}

  defp parse_fetch_item(key, value),
    do: {key, value}

  defp to_sequence(number) when is_integer(number),
    do: Integer.to_string(number)

  defp to_sequence(%Range{first: first, last: first}),
    do: to_sequence(first)

  defp to_sequence(%Range{first: first, last: last}),
    do: [Integer.to_string(first), ":", Integer.to_string(last)]

  defp store_silent([]), do: ""

  defp store_silent([{:silent, _} | _tail]),
    do: ".SILENT"

  defp store_silent([_ | tail]),
    do: store_silent(tail)

  defp process_connection_message(<<"[CAPABILITY ", msg::binary>>, state),
    do: %{state | capability: parse_capability(msg)}

  defp process_connection_message(_msg, state), do: state

  defp handle_tagged_response(cmd_tag, <<"OK ", msg::binary>>, %{cmd_map: cmd_map} = state),
    do: process_command_response(cmd_tag, cmd_map[cmd_tag], msg, state)

  # defp handle_tagged_response(cmd_tag, <<"OK ", msg :: binary>>, state),
  #   do: send_reply(cmd_tag, String.strip(msg), state)
  defp handle_tagged_response(cmd_tag, <<"NO ", msg::binary>>, %{cmd_map: cmd_map} = state),
    do: process_command_error(cmd_tag, cmd_map[cmd_tag], msg, state)

  defp handle_tagged_response(_cmd_tag, <<"BAD ", msg::binary>>, _state),
    do: raise("Bad command #{msg}")

  defp process_command_response(
         cmd_tag,
         %{command: "STARTTLS", caller: caller},
         _msg,
         %{socket: socket, cmd_map: cmd_map, temp: %{username: username, password: password}} =
           state
       ) do
    {:ok, ssl_socket} = Socket.ssl_client(socket)
    state = %{state | cmd_map: Map.delete(cmd_map, cmd_tag)}
    state = %{state | socket: ssl_socket, capability: nil}

    {:noreply,
     send_command(caller, ["LOGIN", " ", quote_string(username), " ", quote_string(password)], %{
       state
       | temp: nil
     })}
  end

  defp process_command_response(
         cmd_tag,
         %{command: "LOGIN", caller: caller},
         msg,
         %{capability: capability} = state
       ) do
    state = remove_command_from_state(state, cmd_tag)
    state = process_connection_message(msg, state)

    if capability == [] do
      {:noreply, send_command(caller, "CAPABILITY", %{state | temp: msg})}
    else
      send_reply(caller, msg, %{state | state: :authenticated})
    end
  end

  defp process_command_response(
         cmd_tag,
         %{command: "LOGOUT", caller: caller},
         _msg,
         %{temp: {:error, error}} = state
       ) do
    state = remove_command_from_state(state, cmd_tag)
    send_error(caller, error, %{state | state: :logged_out})
  end

  defp process_command_response(cmd_tag, %{command: "LOGOUT", caller: caller}, msg, state) do
    send_reply(caller, msg, %{remove_command_from_state(state, cmd_tag) | state: :logged_out})
  end

  defp process_command_response(
         cmd_tag,
         %{command: "SELECT", caller: caller},
         msg,
         %{temp: temp} = state
       ) do
    send_reply(caller, msg, %{
      remove_command_from_state(state, cmd_tag)
      | state: :selected,
        mailbox: parse_mailbox({temp, msg})
    })
  end

  defp process_command_response(
         cmd_tag,
         %{command: "EXAMINE", caller: caller},
         msg,
         %{temp: temp} = state
       ) do
    send_reply(caller, msg, %{
      remove_command_from_state(state, cmd_tag)
      | state: :selected,
        mailbox: parse_mailbox({temp, msg})
    })
  end

  defp process_command_response(
         cmd_tag,
         %{command: "LIST", caller: caller},
         _msg,
         %{temp: temp} = state
       )
       when is_list(temp),
       do: send_reply(caller, Enum.reverse(temp), remove_command_from_state(state, cmd_tag))

  defp process_command_response(
         cmd_tag,
         %{command: "STATUS", caller: caller},
         _msg,
         %{temp: temp} = state
       ),
       do: send_reply(caller, temp, remove_command_from_state(state, cmd_tag))

  defp process_command_response(
         cmd_tag,
         %{command: "FETCH", caller: caller},
         _msg,
         %{temp: temp} = state
       ),
       do: send_reply(caller, Enum.reverse(temp), remove_command_from_state(state, cmd_tag))

  defp process_command_response(
         cmd_tag,
         %{command: "UID FETCH", caller: caller},
         _msg,
         %{temp: temp} = state
       ),
       do: send_reply(caller, Enum.reverse(temp), remove_command_from_state(state, cmd_tag))

  defp process_command_response(
         cmd_tag,
         %{command: "SEARCH", caller: caller},
         _msg,
         %{temp: temp} = state
       ),
       do: send_reply(caller, temp, remove_command_from_state(state, cmd_tag))

  defp process_command_response(
         cmd_tag,
         %{command: "UID SEARCH", caller: caller},
         _msg,
         %{temp: temp} = state
       ),
       do: send_reply(caller, temp, remove_command_from_state(state, cmd_tag))

  defp process_command_response(
         cmd_tag,
         %{command: "STORE", caller: caller},
         _msg,
         %{temp: temp} = state
       ),
       do: send_reply(caller, Enum.reverse(temp), remove_command_from_state(state, cmd_tag))

  defp process_command_response(
         cmd_tag,
         %{command: "CAPABILITY", caller: caller},
         msg,
         %{temp: temp} = state
       ),
       do: send_reply(caller, temp || msg, remove_command_from_state(state, cmd_tag))

  defp process_command_response(cmd_tag, %{command: "COPY", caller: caller}, msg, state),
    do: send_reply(caller, msg, remove_command_from_state(state, cmd_tag))

  defp process_command_response(cmd_tag, %{command: "EXPUNGE", caller: caller}, msg, state),
    do: send_reply(caller, msg, remove_command_from_state(state, cmd_tag))

  defp process_command_response(cmd_tag, %{command: "CLOSE", caller: caller}, msg, state) do
    send_reply(caller, msg, %{
      remove_command_from_state(state, cmd_tag)
      | state: :authenticated,
        mailbox: nil
    })
  end

  defp process_command_response(
         cmd_tag,
         %{command: "IDLE"},
         _msg,
         %{idle_caller: caller, idle_reply_msg: idle_reply_msg} = state
       )
       when not is_nil(idle_reply_msg) do
    send(caller, idle_reply_msg)

    {:noreply,
     %{
       remove_command_from_state(state, cmd_tag)
       | idle_caller: nil,
         idle_reply_msg: nil,
         idle_timer: nil
     }}
  end

  defp process_command_response(cmd_tag, %{command: "IDLE", caller: caller}, _msg, state) do
    send_reply(caller, :ok, %{
      remove_command_from_state(state, cmd_tag)
      | idle_caller: nil,
        idle_reply_msg: nil,
        idle_timer: nil
    })
  end

  defp process_command_response(cmd_tag, %{command: command}, msg, state) do
    Logger.warn("Command not processed: #{cmd_tag} OK #{msg} - #{command} - #{inspect(state)}")
    {:noreply, state}
  end

  defp process_command_error(cmd_tag, %{command: "LOGIN", caller: caller}, msg, state) do
    state = remove_command_from_state(state, cmd_tag)
    {:noreply, send_command(caller, "LOGOUT", %{state | temp: {:error, msg}})}
  end

  defp process_command_error(cmd_tag, %{caller: caller}, msg, state),
    do: send_error(caller, msg, remove_command_from_state(state, cmd_tag))

  defp remove_command_from_state(%{cmd_map: cmd_map} = state, cmd_tag),
    do: %{state | cmd_map: Map.delete(cmd_map, cmd_tag)}

  defp send_command(
         caller,
         command,
         %{socket: socket, cmd_number: cmd_number, cmd_map: cmd_map} = state
       ) do
    cmd_tag = "A#{String.pad_leading(Integer.to_string(cmd_number), 3, "0")}"
    :ok = Socket.send(socket, [cmd_tag, " ", command, "\r\n"])

    %{
      state
      | cmd_number: increment_command_number(cmd_number),
        cmd_map: Map.put_new(cmd_map, cmd_tag, %{command: hd(List.wrap(command)), caller: caller})
    }
  end

  defp increment_command_number(999), do: 1
  defp increment_command_number(number), do: number + 1

  defp fetch_all_data(bytes_required, bytes_read, acc, _state) when bytes_read > bytes_required,
    do: :erlang.iolist_to_binary(Enum.reverse(acc))

  defp fetch_all_data(bytes, bytes, acc, state),
    do: :erlang.iolist_to_binary(Enum.reverse([get_next_line(state) | acc]))

  defp fetch_all_data(bytes_required, bytes_read, acc, state) do
    line = get_next_line(state)
    fetch_all_data(bytes_required, bytes_read + byte_size(line), [line | acc], state)
  end

  defp get_next_line(%{debug: debug}) do
    receive do
      {:ssl, _socket, data} ->
        if debug, do: IO.write(["> [ssl] ", data])
        data

      {:tcp, _socket, data} ->
        if debug, do: IO.write(["> [tcp] ", data])
        data
    end
  end

  defp send_reply(caller, msg, state) do
    GenServer.reply(caller, {:ok, msg})
    {:noreply, state}
  end

  defp send_error(caller, err_msg, state) do
    GenServer.reply(caller, {:error, trim(err_msg)})
    {:noreply, state}
  end

  defp parse_mailbox({"INBOX", msg}),
    do: parse_mailbox({:inbox, msg})

  defp parse_mailbox({name, <<"[READ-ONLY]", _rest::binary>>}),
    do: {name, :r}

  defp parse_mailbox({name, <<"[READ-WRITE]", _rest::binary>>}),
    do: {name, :rw}

  defp parse_capability(string) do
    [list | _] = String.split(trim(string), "]", parts: 2)
    String.split(list, " ")
  end

  if function_exported?(String, :trim, 1) do
    defp trim(string), do: String.trim(string)
  else
    defp trim(string), do: String.strip(string)
  end
end
