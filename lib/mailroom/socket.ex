defmodule Mailroom.Socket do
  @moduledoc """
  Abstracts away working with normal sockets or SSL sockets.

  ## Examples

      {:ok, socket} = #{inspect(__MODULE__)}.connect("localhost", 110)
      {:ok, ssl_socket} = #{inspect(__MODULE__)}.connect("localhost", 110, ssl: true)

      #{inspect(__MODULE__)}.send(socket, "Hello World")
      #{inspect(__MODULE__)}.send(ssl_socket, "Hello World")

      #{inspect(__MODULE__)}.close(socket)
      #{inspect(__MODULE__)}.close(ssl_socket)
  """

  @timeout 15_000

  @type t :: %__MODULE__{}
  defstruct socket: nil, ssl: false, timeout: @timeout, debug: false, connect_opts: []

  @doc """
  Connect to a TCP `server` on `port`

  The following options are available:

    - `ssl` - default `false`, connect via SSL or not
    - `timeout` - default `#{inspect(@timeout)}`, sets the socket connect and receive timeout
    - `debug` - default `false`, if true, will print out connection communication

  ## Examples

      {:ok, socket} = #{inspect(__MODULE__)}.connect("localhost", 110, ssl: true)
  """
  @spec connect(String.t(), integer, Keyword.t()) :: {:ok, t} | {:error, String.t()}
  @connect_opts [packet: :line, reuseaddr: true, active: false, keepalive: true]
  @ssl_connect_opts [depth: 0]
  def connect(server, port, opts \\ []) do
    {state, opts} = parse_opts(opts)
    if state.debug, do: IO.puts("[connecting]")

    connect_opts = Keyword.merge(@connect_opts, opts)
    addr = String.to_charlist(server)

    case do_connect(addr, state.ssl, port, [:binary | connect_opts], state.timeout) do
      {:ok, socket} -> {:ok, %{state | socket: socket, connect_opts: connect_opts}}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp parse_opts(opts, state \\ %__MODULE__{}, acc \\ [])
  defp parse_opts([], state, acc), do: {state, acc}

  defp parse_opts([{:ssl, ssl} | tail], state, acc),
    do: parse_opts(tail, %{state | ssl: ssl}, acc)

  defp parse_opts([{:debug, debug} | tail], state, acc),
    do: parse_opts(tail, %{state | debug: debug}, acc)

  defp parse_opts([opt | tail], state, acc),
    do: parse_opts(tail, state, [opt | acc])

  defp do_connect(addr, true, port, opts, timeout),
    do: :ssl.connect(addr, port, opts, timeout)

  defp do_connect(addr, false, port, opts, timeout),
    do: :gen_tcp.connect(addr, port, opts, timeout)

  @doc """
  Receive a line from the socket

  ## Examples

      {:ok, line} = #{inspect(__MODULE__)}.recv(socket)
  """
  @spec recv(t) :: {:ok, String.t()} | {:error, String.t()}
  def recv(%{debug: debug, ssl: ssl} = socket) do
    case do_recv(socket) do
      {:ok, line} ->
        if debug, do: IO.write(["> ", tag_debug(ssl), line])
        {:ok, String.replace_suffix(line, "\r\n", "")}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp do_recv(%{socket: socket, ssl: true, timeout: timeout}),
    do: :ssl.recv(socket, 0, timeout)

  defp do_recv(%{socket: socket, ssl: false, timeout: timeout}),
    do: :gen_tcp.recv(socket, 0, timeout)

  defp tag_debug(true), do: "[ssl] "
  defp tag_debug(false), do: "[tcp] "

  @doc """
  Send data on a socket

  ## Examples

      :ok = #{inspect(__MODULE__)}.send(socket)
  """
  @spec send(t, iodata) :: :ok | {:error, String.t()}
  def send(%{debug: debug, ssl: ssl} = socket, data) do
    if debug, do: IO.write(["< ", tag_debug(ssl), data])

    case do_send(socket, data) do
      :ok -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_send(%{socket: socket, ssl: true}, data),
    do: :ssl.send(socket, data)

  defp do_send(%{socket: socket, ssl: false}, data),
    do: :gen_tcp.send(socket, data)

  def ssl_client(%{socket: socket, ssl: true}),
    do: socket

  def ssl_client(%{socket: socket, timeout: timeout, connect_opts: connect_opts} = client) do
    case :ssl.connect(socket, @ssl_connect_opts ++ connect_opts, timeout) do
      {:ok, socket} -> {:ok, %{client | socket: socket, ssl: true}}
      {:error, {key, reason}} -> {:error, {key, inspect(reason)}}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @doc """
  Closes the connection

  ## Examples

      :ok = #{inspect(__MODULE__)}.close(socket)
  """
  @spec close(t) :: :ok
  def close(%{debug: debug} = socket) do
    if debug, do: IO.puts("[closing connection]")
    do_close(socket)
  end

  defp do_close(%{socket: socket, ssl: true}),
    do: :ssl.close(socket)

  defp do_close(%{socket: socket, ssl: false}),
    do: :gen_tcp.close(socket)
end
