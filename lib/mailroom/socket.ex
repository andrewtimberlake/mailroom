defmodule Mailroom.Socket do
  defstruct socket: nil, ssl: false, timeout: nil, debug: false

  @timeout 15_000
  def connect(server, port, opts \\ []) do
    ssl = Keyword.get(opts, :ssl, false)
    timeout = Keyword.get(opts, :timeout, @timeout)
    debug = Keyword.get(opts, :debug, false)
    if debug, do: IO.puts("<connecting>")

    connect_opts = [:binary, packet: :line, reuseaddr: true, active: false]
    addr = String.to_charlist(server)
    {:ok, socket} = do_connect(addr, ssl, port, connect_opts, timeout)
    {:ok, %__MODULE__{socket: socket, ssl: ssl, timeout: timeout, debug: debug}}
  end

  defp do_connect(addr, true, port, opts, timeout) do
    :ok = :ssl.start
    :ssl.connect(addr, port, opts, timeout)
  end
  defp do_connect(addr, false, port, opts, timeout),
    do: :gen_tcp.connect(addr, port, opts, timeout)

  def recv(%{debug: debug} = socket) do
    {:ok, message} = do_recv(socket)
    if debug, do: IO.inspect(message)
    {:ok, message}
  end

  defp do_recv(%{socket: socket, ssl: true, timeout: timeout}),
    do: :ssl.recv(socket, 0, timeout)
  defp do_recv(%{socket: socket, ssl: false, timeout: timeout}),
    do: :gen_tcp.recv(socket, 0, timeout)

  def send(%{debug: debug} = socket, data) do
    if debug, do: IO.inspect(data)
    do_send(socket, data)
  end

  defp do_send(%{socket: socket, ssl: true}, data),
    do: :ssl.send(socket, data)
  defp do_send(%{socket: socket, ssl: false}, data),
    do: :gen_tcp.send(socket, data)

  def close(%{debug: debug} = socket) do
    if debug, do: IO.puts("<closing connection>")
    do_close(socket)
  end

  defp do_close(%{socket: socket, ssl: true}),
    do: :ok = :ssl.close(socket)
  defp do_close(%{socket: socket, ssl: false}),
    do: :ok = :gen_tcp.close(socket)
end
