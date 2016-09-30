defmodule Mailroom.POP3 do
  @timeout 15_000

  @doc ~S"""

  """
  def connect(server, username, password, options \\ []) do
    timeout = Keyword.get(options, :timeout, @timeout)
    debug   = Keyword.get(options, :debug, false)
    {:ok, socket} = do_connect(server, options)
    client = %{socket: socket, timeout: timeout, debug: debug}
    case login(client, username, password) do
      :ok -> {:ok, client}
      {:error, reason} -> {:error, :authentication, reason}
    end
  end

  @doc ~S"""

  """
  def close(%{socket: socket} = client) do
    quit(client)
    close_socket(socket)
  end

  def stat(client) do
    {:ok, data} = send_stat(client)
    parse_stat(String.strip(data))
  end

  @doc ~S"""

  """
  def list(client) do
    {:ok, data} = send_list(client)
    data
    |> String.split("\r\n")
    |> Enum.drop(1)
    |> Enum.reduce([], fn
      (".", acc) -> acc
      (stat, acc) -> [parse_stat(stat) | acc]
    end)
    |> Enum.reverse
  end

  @doc ~S"""

  """
  def retrieve(client, mail)
  def retrieve(client, {id, _size}),
    do: retrieve(client, id)
  def retrieve(client, id) do
    :ok = socket_send(client, "RETR #{id}\r\n")
    {:ok, message} = receive_till_end(client)
    [_, message] = String.split(message, "\r\n", parts: 2)
    {:ok, message}
  end

  @doc ~S"""

  """
  def delete(client, mail)
  def delete(client, {id, _size}),
    do: delete(client, id)
  def delete(client, id) do
    :ok = socket_send(client, "DELE #{id}\r\n")
    {:ok, _} = recv(client)
    :ok
  end

  @doc ~S"""

  """
  def reset(client) do
    :ok = socket_send(client, "RSET\r\n")
    {:ok, _} = recv(client)
    :ok
  end

  @doc ~S"""

  """
  def quit(client) do
    :ok = socket_send(client, "QUIT\r\n")
    {:ok, _} = recv(client)
    :ok
  end

  defp login(client, username, password) do
    with {:ok, _} <- recv(client),
         {:ok, _} <- send_user(client, username),
         {:ok, _} <- send_pass(client, password),
      do: :ok
  end

  defp send_user(client, username) do
    :ok = socket_send(client, "USER " <> username <> "\r\n")
    recv(client)
  end

  defp send_pass(client, password) do
    :ok = socket_send(client, "PASS " <> password <> "\r\n")
    recv(client)
  end

  defp send_list(client) do
    :ok = socket_send(client, "LIST\r\n")
    receive_till_end(client)
  end

  defp send_stat(client) do
    :ok = socket_send(client, "STAT\r\n")
    recv(client)
  end

  defp receive_till_end(client, message \\ nil)
  defp receive_till_end(client, nil) do
    {:ok, message} = recv(client)
    process_receive_till_end(client, message)
  end
  defp receive_till_end(client, acc) do
    {:ok, message} = socket_recv(client)
    message = acc <> to_string(message)
    process_receive_till_end(client, message)
  end

  defp process_receive_till_end(client, message) do
    if String.ends_with?(message, "\r\n.\r\n") do
      {:ok, String.replace_trailing(message, "\r\n.\r\n", "")}
    else
      receive_till_end(client, message)
    end
  end

  defp parse_stat(data, count \\ "", size \\ nil)
  defp parse_stat("", count, size),
    do: {String.to_integer(count), String.to_integer(size)}
  defp parse_stat(" ", count, size),
    do: {String.to_integer(count), String.to_integer(size)}
  defp parse_stat(<<" ", rest :: binary>>, count, nil),
    do: parse_stat(rest, count, "")
  defp parse_stat(<<char :: binary-size(1), rest :: binary>>, count, nil),
      do: parse_stat(rest, count <> char, nil)
  defp parse_stat(<<char :: binary-size(1), rest :: binary>>, count, size),
    do: parse_stat(rest, count, size <> char)

  defp do_connect(server, options) do
    ssl = Keyword.get(options, :ssl, false)
    timeout = Keyword.get(options, :timeout, @timeout)
    port = Keyword.get(options, :port, (if ssl, do: 995, else: 110))
    opts = [:binary, packet: :line, reuseaddr: true, active: false]
    addr = String.to_charlist(server)
    if ssl do
      :ok = :ssl.start
      {:ok, socket} = :ssl.connect(addr, port, opts, timeout)
    else
      {:ok, socket} = :gen_tcp.connect(addr, port, opts, timeout)
    end
  end

  defp recv(client) do
    {:ok, msg} = socket_recv(client)
    case msg do
      <<"+OK", msg :: binary>> ->
        {:ok, msg}
      <<"-ERR", reason :: binary>> ->
        {:error, String.strip(reason)}
    end
  end

  defp socket_recv(%{socket: {:sslsocket, _, _} = socket, debug: debug, timeout: timeout}) do
    {:ok, message} = :ssl.recv(socket, 0, timeout)
    message = to_string(message)
    if debug, do: IO.inspect(message)
    {:ok, message}
  end
  defp socket_recv(%{socket: socket, timeout: timeout, debug: debug}) do
    {:ok, message} = :gen_tcp.recv(socket, 0, timeout)
    message = to_string(message)
    if debug, do: IO.inspect(message)
    {:ok, message}
  end

  defp socket_send(%{socket: {:sslsocket, _, _} = socket, debug: debug}, data) when is_binary(data) do
    if debug, do: IO.inspect(data)
    data = String.to_charlist(data)
    :ssl.send(socket, data)
  end
  defp socket_send(%{socket: socket, debug: debug}, data) when is_binary(data) do
    if debug, do: IO.inspect(data)
    :gen_tcp.send(socket, data)
  end

  defp close_socket({:sslsocket, _, _} = socket),
    do: :ok = :ssl.close(socket)
  defp close_socket(socket),
    do: :ok = :gen_tcp.close(socket)
end
