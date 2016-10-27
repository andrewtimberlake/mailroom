defmodule Mailroom.IMAP do
  require Logger
  use GenServer

  import Mailroom.IMAP.Utils

  defmodule State do
    @moduledoc false
    defstruct socket: nil, state: :unauthenticated, ssl: false, debug: false, cmd_map: %{}, cmd_number: 1, capability: [], flags: [], permanent_flags: [], uid_validity: nil, uid_next: nil, highest_mod_seq: nil, recent: 0, exists: 0, temp: nil
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

  def state(pid),
    do: GenServer.call(pid, :state)

  def init(opts) do
    {:ok, %{debug: opts.debug, ssl: opts.ssl}}
  end

  def handle_call({:connect, server, port}, from, state) do
    {:ok, socket} = Socket.connect(server, port, ssl: state.ssl, debug: state.debug, active: true)
    {:noreply, %State{socket: socket, state: :unauthenticated, debug: state.debug, ssl: state.ssl, cmd_map: %{connect: from}}}
  end
  def handle_call({:login, username, password}, from, %{capability: capability} = state) do
    if Enum.member?(capability, "STARTTLS") do
      {:noreply, send_command(from, "STARTTLS", %{state | temp: %{username: username, password: password}})}
    else
      {:noreply, send_command(from, ["LOGIN", " ", username, " ", password], state)}
    end
  end

  def handle_call({:select, :inbox}, from, state),
    do: handle_call({:select, "INBOX"}, from, state)
  def handle_call({:select, mailbox}, from, state),
    do: {:noreply, send_command(from, ["SELECT", " ", mailbox], state)}

  def handle_call(:email_count, _from, %{exists: exists} = state),
    do: {:reply, exists, state}

  def handle_call(:recent_count, _from, %{recent: recent} = state),
    do: {:reply, recent, state}

  def handle_call(:state, _from, %{state: connection_state} = state),
    do: {:reply, connection_state, state}

  def handle_info({:ssl, _socket, msg}, state) do
    if state.debug, do: IO.write(["> [ssl] ", msg])
    handle_response(msg, state)
  end
  def handle_info({:tcp, _socket, msg}, state) do
    if state.debug, do: IO.write(["> [tcp] ", msg])
    handle_response(msg, state)
  end
  def handle_info(msg, state) do
    Logger.info("handle_info(#{inspect(msg)}, #{inspect(state)})")
    {:noreply, state}
  end

  defp handle_response(<<"* OK ", msg :: binary>>, %{state: :unauthenticated, cmd_map: %{connect: caller} = cmd_map} = state) do
    state = process_connection_message(msg, state)
    GenServer.reply(caller, {:ok, msg})
    {:noreply, %{state | cmd_map: Map.delete(cmd_map, :connect)}}
  end

  defp handle_response(<<"* OK [PERMANENTFLAGS ", msg :: binary>>, state),
    do: {:noreply, %{state | permanent_flags: parse_list(msg)}}
  defp handle_response(<<"* OK [UIDVALIDITY ", msg :: binary>>, state),
    do: {:noreply, %{state | uid_validity: parse_number(msg)}}
  defp handle_response(<<"* OK [UIDNEXT ", msg :: binary>>, state),
    do: {:noreply, %{state | uid_next: parse_number(msg)}}
  defp handle_response(<<"* OK [HIGHESTMODSEQ ", msg :: binary>>, state),
    do: {:noreply, %{state | highest_mod_seq: parse_number(msg)}}
  defp handle_response(<<"* OK [CAPABILITY ", msg :: binary>>, state),
    do: {:noreply, %{state | capability: parse_list(msg)}}
  defp handle_response(<<"* CAPABILITY ", msg :: binary>>, state),
    do: {:noreply, %{state | capability: parse_list(msg)}}
  defp handle_response(<<"* FLAGS ", msg :: binary>>, state),
    do: {:noreply, %{state | flags: parse_list(msg)}}
  defp handle_response(<<"* BYE ", _msg :: binary>>, state),
    do: {:noreply, state}
  defp handle_response(<<"* ", msg :: binary>>, state) do
    state = case String.split(String.strip(msg), " ") do
              [number, "EXISTS"] -> %{state | exists: String.to_integer(number)}
              [number, "RECENT"] -> %{state | recent: String.to_integer(number)}
              _ ->
                Logger.warn("Unknown untagged response: #{msg}")
                state
            end
    {:noreply, state}
  end
  defp handle_response(<<cmd_tag :: binary-size(4), " ", msg :: binary>>, state),
    do: handle_tagged_response(cmd_tag, msg, state)
  defp handle_response(msg, state) do
    Logger.warn("handle_response(socket, #{inspect(msg)}, #{inspect(state)})")
    {:noreply, state}
  end

  defp process_connection_message(<<"[CAPABILITY ", msg :: binary>>, state),
    do: %{state | capability: parse_list(msg)}
  defp process_connection_message(_msg, state), do: state

  defp handle_tagged_response(cmd_tag, <<"OK ", msg :: binary>>, %{cmd_map: cmd_map} = state),
    do: process_command_response(cmd_tag, cmd_map[cmd_tag], msg, state)
  # defp handle_tagged_response(cmd_tag, <<"OK ", msg :: binary>>, state),
  #   do: send_reply(cmd_tag, String.strip(msg), state)
  defp handle_tagged_response(cmd_tag, <<"NO ", msg :: binary>>, %{cmd_map: cmd_map} = state),
    do: process_command_error(cmd_tag, cmd_map[cmd_tag], msg, state)
  defp handle_tagged_response(_cmd_tag, <<"BAD ", msg :: binary>>, _state),
    do: raise "Bad command #{msg}"

  defp process_command_response(cmd_tag, %{command: "STARTTLS", caller: caller}, _msg, %{socket: socket, cmd_map: cmd_map, temp: %{username: username, password: password}} = state) do
    {:ok, ssl_socket} = Socket.ssl_client(socket)
    state = %{state | cmd_map: Map.delete(cmd_map, cmd_tag)}
    state = %{state | socket: ssl_socket, capability: nil}
    {:noreply, send_command(caller, ["LOGIN", " ", username, " ", password], %{state | temp: nil})}
  end
  defp process_command_response(cmd_tag, %{command: "LOGIN", caller: caller}, msg, state) do
    state = remove_command_from_state(state, cmd_tag)
    state = process_connection_message(msg, state)
    send_reply(caller, msg, %{state | state: :authenticated})
  end
  defp process_command_response(cmd_tag, %{command: "LOGOUT", caller: caller}, _msg, %{temp: {:error, error}} = state) do
    state = remove_command_from_state(state, cmd_tag)
    send_error(caller, error, state)
  end
  defp process_command_response(cmd_tag, %{command: "SELECT", caller: caller}, msg, state),
    do: send_reply(caller, msg, %{remove_command_from_state(state, cmd_tag) | state: :selected})
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

  defp send_command(caller, command, %{socket: socket, cmd_number: cmd_number, cmd_map: cmd_map} = state) do
    cmd_tag = "A#{String.pad_leading(Integer.to_string(cmd_number), 3, "0")}"
    :ok = Socket.send(socket, [cmd_tag, " ", command, "\r\n"])
    %{state | cmd_number: cmd_number + 1, cmd_map: Map.put_new(cmd_map, cmd_tag, %{command: hd(List.wrap(command)), caller: caller})}
  end

  defp send_reply(caller, msg, state) do
    GenServer.reply(caller, {:ok, msg})
    {:noreply, state}
  end

  defp send_error(caller, err_msg, state) do
    GenServer.reply(caller, {:error, String.strip(err_msg)})
    {:noreply, state}
  end
end
