defmodule Mailroom.TestServer.Application do
  use Application

  def start(_type, _args) do
    DynamicSupervisor.start_link(strategy: :one_for_one, name: Mailroom.TestServer.Supervisor)
  end
end

defmodule Mailroom.TestServer do
  use GenServer

  @tcp_opts [:binary, packet: :line, active: false, reuseaddr: true]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    ssl = Keyword.get(opts, :ssl, false)
    {:ok, socket} = get_socket(ssl)
    {:ok, port} = get_port(socket)
    {:ok, %{address: "localhost", port: port, socket: socket, ssl: ssl, result: :ok}}
  end

  def call(pid, request) do
    GenServer.call(pid, request, :infinity)
  end

  def cast(pid, request) do
    GenServer.cast(pid, request)
  end

  def handle_call(:setup, _from, %{address: address, port: port} = state),
    do: {:reply, {address, port}, state}

  def handle_call(:on_exit, _from, state),
    do: {:reply, state.result, state}

  def handle_call(request, from, state) do
    IO.puts("handle_call(#{inspect(request)}, #{inspect(from)}, #{inspect(state)})")
    {:reply, :ok, state}
  end

  def handle_cast({:start, expectations}, state) do
    state = Map.put(state, :expectations, expectations)
    {:ok, client} = accept_connection(state.socket)
    result = serve_client(client, state.expectations)
    state = Map.put(state, :result, result)
    {:noreply, state}
  end

  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  def serve_client(socket, conversation, response \\ nil)

  def serve_client(socket, [{:connect, response, options} | tail], nil) do
    socket_send(socket, response)
    socket = upgrade_to_ssl(socket, options)
    {:ok, data} = socket_recv(socket)
    serve_client(socket, tail, data)
  end

  def serve_client(socket, [{[data], response, options} | tail], data) do
    socket_send(socket, response)
    socket = upgrade_to_ssl(socket, options)
    {:ok, data} = socket_recv(socket)
    serve_client(socket, tail, data)
  end

  def serve_client(socket, [{[data], response, _options}], data) do
    socket_send(socket, response)
    :ok
  end

  def serve_client(socket, [{data, response, _options}], data) do
    socket_send(socket, response)
    :ok
  end

  def serve_client(socket, [{[data | data_tail], response, options} | tail], data) do
    {:ok, data} = socket_recv(socket)
    serve_client(socket, [{data_tail, response, options} | tail], data)
  end

  def serve_client(socket, [{data, response, options} | tail], data) do
    socket_send(socket, response)
    socket = upgrade_to_ssl(socket, options)
    {:ok, data} = socket_recv(socket)
    serve_client(socket, tail, data)
  end

  def serve_client(socket, [{expected, _response, _options} | _tail], actual) do
    socket_send(socket, "Expected #{inspect(expected)} but received #{inspect(actual)}\r\n")
    {:error, expected, actual}
  end

  defp upgrade_to_ssl({:sslsocket, _, _} = socket, _options), do: socket

  defp upgrade_to_ssl(socket, options) do
    if Keyword.get(options, :ssl) do
      opts = [
        [certfile: Path.join(__DIR__, "certificate.pem"), keyfile: Path.join(__DIR__, "key.pem")]
        | @tcp_opts
      ]

      {:ok, socket} = handshake(socket, opts, 1_000)

      socket
    else
      socket
    end
  end

  def start(opts \\ []) do
    case DynamicSupervisor.start_child(
           Mailroom.TestServer.Supervisor,
           {Mailroom.TestServer, opts}
         ) do
      {:ok, pid} ->
        {address, port} = call(pid, :setup)

        ExUnit.Callbacks.on_exit({__MODULE__, pid}, fn ->
          case __MODULE__.call(pid, :on_exit) do
            :ok ->
              :ok

            {:error, expected, actual} ->
              raise ExUnit.AssertionError,
                    "TestServer expected #{inspect(expected)} but received #{inspect(actual)}"
          end
        end)

        %{pid: pid, address: address, port: port}

      other ->
        other
    end
  end

  def expect(server, func) do
    expectations =
      func.([])
      |> Enum.reverse()
      |> add_tags()

    cast(server.pid, {:start, expectations})
  end

  def on(expectations, cmd, resp, options \\ []) do
    [{cmd, resp, options} | expectations]
  end

  def tagged(expectations, cmd, resp, options \\ []) do
    [{:tagged, cmd, resp, options} | expectations]
  end

  defp add_tags(list, cmd_number \\ 0)
  defp add_tags([], _), do: []

  defp add_tags([{:tagged, "IDLE\r\n" = cmd, resp, options} | tail], cmd_number) do
    [{add_tag(cmd, cmd_number), add_tag(resp, cmd_number), options} | add_tags(tail, cmd_number)]
  end

  defp add_tags([{:tagged, cmd, resp, options} | tail], cmd_number) do
    [
      {add_tag(cmd, cmd_number), add_tag(resp, cmd_number), options}
      | add_tags(tail, cmd_number + 1)
    ]
  end

  defp add_tags([head | tail], cmd_number) do
    [head | add_tags(tail, cmd_number + 1)]
  end

  defp add_tag([], _), do: []

  defp add_tag([command | tail], cmd_number),
    do: [add_tag(command, cmd_number) | add_tag(tail, cmd_number)]

  defp add_tag(command, _) when is_atom(command), do: command
  defp add_tag("DONE\r\n", _), do: "DONE\r\n"
  defp add_tag(<<"*", _rest::binary>> = command, _), do: command
  defp add_tag(<<"+", _rest::binary>> = command, _), do: command

  defp add_tag(command, cmd_number),
    do: "A#{String.pad_leading(to_string(cmd_number), 3, "0")} #{command}"

  defp get_socket(false),
    do: :gen_tcp.listen(0, @tcp_opts)

  defp get_socket(true) do
    :ok = :ssl.start()

    :ssl.listen(0, [
      [certfile: Path.join(__DIR__, "certificate.pem"), keyfile: Path.join(__DIR__, "key.pem")]
      | @tcp_opts
    ])
  end

  defp get_port({:sslsocket, _, {socket, _}}),
    do: get_port(socket)

  defp get_port(socket),
    do: :inet.port(socket)

  defp accept_connection({:sslsocket, _, _} = socket) do
    {:ok, socket} = :ssl.transport_accept(socket)

    handshake(socket, 1_000)
  end

  defp accept_connection(socket),
    do: :gen_tcp.accept(socket, 1_000)

  defp socket_send({:sslsocket, _, _} = socket, data),
    do: :ssl.send(socket, data)

  defp socket_send(socket, data),
    do: :gen_tcp.send(socket, data)

  defp socket_recv({:sslsocket, _, _} = socket),
    do: :ssl.recv(socket, 0, 1_000)

  defp socket_recv(socket),
    do: :gen_tcp.recv(socket, 0, 1_000)

  if Code.ensure_loaded?(:ssl) &&
       function_exported?(:ssl, :handshake, 2) do
    defp handshake(socket, timeout) do
      :ssl.handshake(socket, timeout)
    end
  else
    defp handshake(socket, timeout) do
      :ok = :ssl.ssl_accept(socket, timeout)
      {:ok, socket}
    end
  end

  if Code.ensure_loaded?(:ssl) &&
       function_exported?(:ssl, :handshake, 3) do
    defp handshake(socket, opts, timeout) do
      :ssl.handshake(socket, opts, timeout)
    end
  else
    defp handshake(socket, opts, timeout) do
      :ok = :ssl.ssl_accept(socket, opts, timeout)
      {:ok, socket}
    end
  end
end
