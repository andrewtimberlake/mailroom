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
  @type t :: %__MODULE__{}
  defstruct socket: nil, ssl: false, timeout: nil, debug: false

  @timeout 15_000
  @doc """
  Connect to a TCP `server` on `port`

  The following options are available:

    - `ssl` - default `false`, connect via SSL or not
    - `timeout` - default `#{inspect(@timeout)}`, sets the socket connect and receive timeout
    - `debug` - default `false`, if true, will print out connection communication

  ## Examples

      {:ok, socket} = #{inspect(__MODULE__)}.connect("localhost", 110, ssl: true)
  """
  @spec connect(String.t, integer, Keyword.t) :: {:ok, t} | {:error, String.t}
  @connect_opts [:binary, packet: :line, reuseaddr: true, active: false]
  def connect(server, port, opts \\ []) do
    ssl = Keyword.get(opts, :ssl, false)
    timeout = Keyword.get(opts, :timeout, @timeout)
    debug = Keyword.get(opts, :debug, false)
    if debug, do: IO.puts("[connecting]")

    addr = String.to_charlist(server)
    case do_connect(addr, ssl, port, @connect_opts, timeout) do
      {:ok, socket} -> {:ok, %__MODULE__{socket: socket, ssl: ssl, timeout: timeout, debug: debug}}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp do_connect(addr, true, port, opts, timeout) do
    :ok = :ssl.start
    :ssl.connect(addr, port, opts, timeout)
  end
  defp do_connect(addr, false, port, opts, timeout),
    do: :gen_tcp.connect(addr, port, opts, timeout)

  @doc """
  Receive a line from the socket

  ## Examples

      {:ok, line} = #{inspect(__MODULE__)}.recv(socket)
  """
  @spec recv(t) :: {:ok, String.t} | {:error, String.t}
  def recv(%{debug: debug} = socket) do
    case do_recv(socket) do
      {:ok, line} ->
        if debug, do: IO.write(["> ", line])
        {:ok, String.replace_suffix(line, "\r\n", "")}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp do_recv(%{socket: socket, ssl: true, timeout: timeout}),
    do: :ssl.recv(socket, 0, timeout)
  defp do_recv(%{socket: socket, ssl: false, timeout: timeout}),
    do: :gen_tcp.recv(socket, 0, timeout)

  @doc """
  Send data on a socket

  ## Examples

      :ok = #{inspect(__MODULE__)}.send(socket)
  """
  @spec send(t, String.t) :: :ok | {:error, String.t}
  def send(%{debug: debug} = socket, data) do
    if debug, do: IO.write(["< ", data])
    case do_send(socket, data) do
      :ok -> :ok
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp do_send(%{socket: socket, ssl: true}, data),
    do: :ssl.send(socket, data)
  defp do_send(%{socket: socket, ssl: false}, data),
    do: :gen_tcp.send(socket, data)

  def ssl_client(%{socket: socket, ssl: true} = socket),
    do: socket
  def ssl_client(%{socket: socket, timeout: timeout} = client) do
    :ok = :ssl.start
    case :ssl.connect(socket, @connect_opts, timeout) do
      {:ok, socket} -> {:ok, %{client | socket: socket, ssl: true}}
      {:error, reason} -> {:error, to_string(reason)}
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
