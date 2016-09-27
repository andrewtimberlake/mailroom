defmodule Mailroom.POP3 do
  @doc ~S"""

  """
  def connect(server, username, password, options \\ []) do
    {:ok, socket} = do_connect(server, options)
    :ok = login(socket, username, password)
    {:ok, socket}
  end

  @doc ~S"""

  """
  def close(socket) do
    quit(socket)
    close_socket(socket)
  end

  def stat(socket) do
    {:ok, data} = send_stat(socket)
    parse_stat(String.strip(data))
  end

  @doc ~S"""

  """
  def each_mail(socket, func) do
    {:ok, data} = send_list(socket)
    data
    |> String.split("\r\n")
    |> Enum.drop(1)
    |> Enum.each(fn
      "." -> nil
      stat ->
        {id, size} = parse_stat(stat)
        func.({id, size})
    end)
  end

  @doc ~S"""

  """
  def retrieve(client, mail)
  def retrieve(socket, {id, _size}),
    do: retrieve(socket, id)
  def retrieve(socket, id) do
    :ok = socket_send(socket, "RETR #{id}\r\n")
    {:ok, message} = receive_till_end(socket)
    [_, message] = String.split(message, "\r\n", parts: 2)
    {:ok, message}
  end

  @doc ~S"""

  """
  def delete(client, mail)
  def delete(socket, {id, _size}),
    do: delete(socket, id)
  def delete(socket, id) do
    :ok = socket_send(socket, "DELE #{id}\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  @doc ~S"""

  """
  def reset(socket) do
    :ok = socket_send(socket, "RSET\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  @doc ~S"""

  """
  def quit(socket) do
    :ok = socket_send(socket, "QUIT\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  defp login(socket, username, password) do
    with {:ok, _} = recv(socket),
         {:ok, _} = send_user(socket, username),
         {:ok, _} = send_pass(socket, password),
      do: :ok
  end

  defp send_user(socket, username) do
    :ok = socket_send(socket, "USER " <> username <> "\r\n")
    recv(socket)
  end

  defp send_pass(socket, password) do
    :ok = socket_send(socket, "PASS " <> password <> "\r\n")
    recv(socket)
  end

  defp send_list(socket) do
    :ok = socket_send(socket, "LIST\r\n")
    receive_till_end(socket)
  end

  defp send_stat(socket) do
    :ok = socket_send(socket, "STAT\r\n")
    recv(socket)
  end

  defp receive_till_end(socket, message \\ nil)
  defp receive_till_end(socket, nil) do
    {:ok, message} = recv(socket)
    process_receive_till_end(socket, message)
  end
  defp receive_till_end(socket, acc) do
    {:ok, message} = socket_recv(socket)
    message = acc <> to_string(message)
    process_receive_till_end(socket, message)
  end

  defp process_receive_till_end(socket, message) do
    if String.ends_with?(message, "\r\n.\r\n") do
      {:ok, String.replace_trailing(message, "\r\n.\r\n", "")}
    else
      receive_till_end(socket, message)
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
      do: parse_stat(rest, char <> count, nil)
  defp parse_stat(<<char :: binary-size(1), rest :: binary>>, count, size),
    do: parse_stat(rest, count, char <> size)

  defp do_connect(server, options) do
    ssl = Keyword.get(options, :ssl, false)
    port = Keyword.get(options, :port, (if ssl, do: 995, else: 110))
    opts = [packet: :raw, reuseaddr: true, active: false]
    addr = String.to_charlist(server)
    if ssl do
      :ok = :ssl.start
      {:ok, socket} = :ssl.connect(addr, port, opts)
    else
      {:ok, socket} = :gen_tcp.connect(addr, port, opts)
    end
  end

  defp recv(socket) do
    {:ok, msg} = socket_recv(socket)
    case msg do
      <<"+OK", msg :: binary>> ->
        {:ok, to_string(msg)}
      <<"-ERR", reason :: binary>> ->
        {:error, String.strip(to_string(reason))}
    end
  end

  defp socket_recv({:sslsocket, _, _} = socket) do
    {:ok, message} = :ssl.recv(socket, 0)
    message = to_string(message)
    IO.inspect(message)
    {:ok, message}
  end

  defp socket_send({:sslsocket, _, _} = socket, data) when is_binary(data) do
    IO.inspect(data)
    data = String.to_charlist(data)
    :ssl.send(socket, data)
  end

  defp close_socket({:sslsocket, _, _} = socket),
    do: :ok = :ssl.close(socket)
end
