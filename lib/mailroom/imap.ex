defmodule Mailroom.IMAP do
  require Logger
  use GenServer

  defmodule State do
    @moduledoc false
    defstruct socket: nil, state: nil, ssl: false, debug: false, cmd_map: %{}, cmd_number: 1, capability: [], flags: [], permanent_flags: [], uid_validity: nil, uid_next: nil, highest_mod_seq: nil, recent: 0, exists: 0, temp: nil
  end

  @moduledoc """
  Handles communication with a POP3 server.

  ## Example:

      {:ok, client} = #{inspect(__MODULE__)}.connect("pop3.server", "username", "password")
      client
      |> #{inspect(__MODULE__)}.list
      |> Enum.each(fn(mail)) ->
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

  alias Mailroom.Socket

  @doc """
  Connect to the POP3 server

  The following options are available:

    - `ssl` - default `false`, connect via SSL or not
    - `port` - default `110` (`995` if SSL), the port to connect to
    - `timeout` - default `15_000`, the timeout for connection and communication

  ## Examples:

      #{inspect(__MODULE__)}.connect("pop3.myserver", "me", "secret", ssl: true)
      {:ok, %#{inspect(__MODULE__)}{}}
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
    do: GenServer.call(pid, {:select, mailbox_name})

  def email_count(pid),
    do: GenServer.call(pid, :email_count)

  def recent_count(pid),
    do: GenServer.call(pid, :recent_count)

  def init(opts) do
    {:ok, %{debug: opts.debug, ssl: opts.ssl}}
  end

  def handle_call({:connect, server, port}, from, state) do
    {:ok, socket} = Socket.connect(server, port, ssl: state.ssl, debug: state.debug, active: true)
    {:noreply, %State{socket: socket, state: :connect, debug: state.debug, ssl: state.ssl, cmd_map: %{connect: from}}}
  end
  def handle_call({:login, username, password}, from, %{socket: socket, capability: capability} = state) do
    if Enum.member?(capability, "STARTTLS") do
      {:noreply, send_command(socket, from, "STARTTLS", %{state | temp: %{username: username, password: password}})}
    else
      {:noreply, send_command(socket, from, ["LOGIN", " ", username, " ", password], state)}
    end
  end

  def handle_call({:select, :inbox}, from, state),
    do: handle_call({:select, "INBOX"}, from, state)
  def handle_call({:select, mailbox}, from, %{socket: socket} = state),
    do: {:noreply, send_command(socket, from, ["SELECT", " ", mailbox], state)}

  def handle_call(:email_count, _from, %{exists: exists} = state),
    do: {:reply, exists, state}

  def handle_call(:recent_count, _from, %{recent: recent} = state),
    do: {:reply, recent, state}

  def handle_info({:ssl, socket, msg}, state) do
    if state.debug, do: IO.write(["> [ssl] ", msg])
    handle_response(socket, msg, state)
  end
  def handle_info({:tcp, socket, msg}, state) do
    if state.debug, do: IO.write(["> [tcp] ", msg])
    handle_response(socket, msg, state)
  end
  def handle_info(msg, state) do
    Logger.info("handle_info(#{inspect(msg)}, #{inspect(state)})")
    {:noreply, state}
  end

  defp handle_response(_socket, <<"* OK ", msg :: binary>>, %{state: :connect, cmd_map: %{connect: caller} = cmd_map} = state) do
    state = process_connection_message(msg, state)
    GenServer.reply(caller, {:ok, msg})
    {:noreply, %{state | state: :authenticated, cmd_map: Map.delete(cmd_map, :connect)}}
  end
  defp handle_response(_socket, <<"* NO ", msg :: binary>>, %{state: :connect, cmd_map: %{connect: caller} = cmd_map} = state) do
    GenServer.reply(caller, {:error, msg})
    {:noreply, %{state | state: nil, cmd_map: Map.delete(cmd_map, :connect)}}
  end

  defp handle_response(_socket, <<"* OK [PERMANENTFLAGS (", msg :: binary>>, state),
    do: {:noreply, %{state | permanent_flags: parse_list(msg)}}
  defp handle_response(_socket, <<"* OK [UIDVALIDITY ", msg :: binary>>, state),
    do: {:noreply, %{state | uid_validity: parse_number(msg)}}
  defp handle_response(_socket, <<"* OK [UIDNEXT ", msg :: binary>>, state),
    do: {:noreply, %{state | uid_next: parse_number(msg)}}
  defp handle_response(_socket, <<"* OK [HIGHESTMODSEQ ", msg :: binary>>, state),
    do: {:noreply, %{state | highest_mod_seq: parse_number(msg)}}
  defp handle_response(_socket, <<"* OK [CAPABILITY ", msg :: binary>>, state),
    do: {:noreply, %{state | capability: parse_list(msg)}}
  defp handle_response(_socket, <<"* CAPABILITY ", msg :: binary>>, state),
    do: {:noreply, %{state | capability: parse_list(msg)}}
  defp handle_response(_socket, <<"* FLAGS (", msg :: binary>>, state),
    do: {:noreply, %{state | flags: parse_list(msg)}}
  defp handle_response(_socket, <<"* ", msg :: binary>>, state) do
    state = case String.split(String.strip(msg), " ") do
              [number, "EXISTS"] -> %{state | exists: String.to_integer(number)}
              [number, "RECENT"] -> %{state | recent: String.to_integer(number)}
              _ -> Logger.warn("Unknown incedental command: #{msg}")
            end
    {:noreply, state}
  end
  defp handle_response(socket, <<cmd_tag :: binary-size(4), " ", msg :: binary>>, state),
    do: handle_tagged_response(socket, cmd_tag, msg, state)
  defp handle_response(_socket, msg, state) do
    Logger.warn("handle_response(socket, #{inspect(msg)}, #{inspect(state)})")
    {:noreply, state}
  end

  defp process_connection_message(<<"[CAPABILITY ", msg :: binary>>, state),
    do: %{state | capability: parse_list(msg)}
  defp process_connection_message(_msg, state), do: state

  defp handle_tagged_response(socket, cmd_tag, <<"OK ", msg :: binary>>, %{cmd_map: cmd_map} = state),
    do: process_command_response(socket, cmd_tag, cmd_map[cmd_tag], msg, state)
  defp handle_tagged_response(socket, cmd_tag, <<"OK ", msg :: binary>>, state),
    do: send_reply(socket, cmd_tag, String.strip(msg), state)
  defp handle_tagged_response(socket, cmd_tag, <<"NO ", msg :: binary>>, state),
    do: send_error(socket, cmd_tag, String.strip(msg), state)
  defp handle_tagged_response(_socket, _cmd_tag, <<"BAD ", msg :: binary>>, _state),
    do: raise "Bad command #{msg}"

  defp process_command_response(_socket, cmd_tag, %{command: "STARTTLS", caller: caller}, _msg, %{socket: socket, cmd_map: cmd_map, temp: %{username: username, password: password}} = state) do
    {:ok, ssl_socket} = Socket.ssl_client(socket)
    state = %{state | cmd_map: Map.delete(cmd_map, cmd_tag)}
    state = %{state | socket: ssl_socket, capability: nil}
    {:noreply, send_command(ssl_socket, caller, ["LOGIN", " ", username, " ", password], %{state | temp: nil})}
  end
  defp process_command_response(_socket, cmd_tag, %{command: "LOGIN", caller: caller}, msg, %{cmd_map: cmd_map} = state) do
    state = remove_command_from_state(state, cmd_tag)
    state = process_connection_message(msg, state)
    GenServer.reply(caller, {:ok, msg})
    {:noreply, %{state | state: :authenticated, cmd_map: Map.delete(cmd_map, :connect)}}
  end
  defp process_command_response(_socket, cmd_tag, %{command: "SELECT", caller: caller}, msg, %{cmd_map: cmd_map} = state) do
    state = remove_command_from_state(state, cmd_tag)
    GenServer.reply(caller, {:ok, msg})
    {:noreply, %{state | state: :selected, cmd_map: Map.delete(cmd_map, :connect)}}
  end
  defp process_command_response(_socket, cmd_tag, %{command: command}, msg, state) do
    Logger.warn("Command not processed: #{cmd_tag} OK #{msg} - #{command} - #{inspect(state)}")
    {:noreply, state}
  end

  defp remove_command_from_state(%{cmd_map: cmd_map} = state, cmd_tag),
    do: %{state | cmd_map: Map.delete(cmd_map, cmd_tag)}

  defp send_command(socket, caller, command, %{cmd_number: cmd_number, cmd_map: cmd_map} = state) do
    cmd_tag = "A#{String.pad_leading(Integer.to_string(cmd_number), 3, "0")}"
    :ok = Socket.send(socket, [cmd_tag, " ", command, "\r\n"])
    %{state | cmd_number: cmd_number + 1, cmd_map: Map.put_new(cmd_map, cmd_tag, %{command: hd(List.wrap(command)), caller: caller})}
  end

  defp send_reply(_socket, cmd_tag, msg, %{cmd_map: cmd_map} = state) do
    caller = Map.get(cmd_map, cmd_tag)
    GenServer.reply(caller, {:ok, msg})
    {:noreply, %{state | cmd_map: Map.delete(cmd_map, cmd_tag)}}
  end

  defp send_error(_socket, cmd_tag, msg, %{cmd_map: cmd_map} = state) do
    caller = Map.get(cmd_map, cmd_tag)
    GenServer.reply(caller, {:error, msg})
    {:noreply, %{state | cmd_map: Map.delete(cmd_map, cmd_tag)}}
  end

  defp parse_list(string, temp \\ "", acc \\ [])
  defp parse_list(<<")", _rest :: binary>>, temp, acc),
    do: Enum.reverse([temp | acc])
  defp parse_list(<<"]", _rest :: binary>>, temp, acc),
    do: Enum.reverse([temp | acc])
  defp parse_list(<<"(", rest :: binary>>, temp, acc),
    do: parse_list(rest, temp, acc)
  defp parse_list(<<" ", rest :: binary>>, temp, acc),
    do: parse_list(rest, "", [temp | acc])
  defp parse_list(<<char :: integer, rest :: binary>>, temp, acc),
    do: parse_list(rest, <<temp :: binary, char>>, acc)

  defp parse_number(string, acc \\ "")
  0..9
  |> Enum.map(&Integer.to_string/1)
  |> Enum.each(fn(digit) ->
    defp parse_number(<<unquote(digit), rest :: binary>>, acc),
      do: parse_number(rest, <<acc :: binary, unquote(digit)>>)
  end)
  defp parse_number(_, acc),
    do: String.to_integer(acc)
end
