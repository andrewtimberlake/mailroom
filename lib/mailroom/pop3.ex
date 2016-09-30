defmodule Mailroom.POP3 do
  alias Mailroom.Socket

  @timeout 15_000

  @doc ~S"""

  """
  def connect(server, username, password, options \\ []) do
    ssl = Keyword.get(options, :ssl, false)
    port = Keyword.get(options, :port, (if ssl, do: 995, else: 110))
    {:ok, socket} = Socket.connect(server, port, options)
    case login(socket, username, password) do
      :ok -> {:ok, socket}
      {:error, reason} -> {:error, :authentication, reason}
    end
  end

  @doc ~S"""

  """
  def close(socket) do
    quit(socket)
    Socket.close(socket)
  end

  def stat(socket) do
    {:ok, data} = send_stat(socket)
    parse_stat(String.strip(data))
  end

  @doc ~S"""

  """
  def list(socket) do
    {:ok, data} = send_list(socket)
    data
    |> Enum.drop(1)
    |> Enum.reduce([], fn
      (".", acc) -> acc
      (stat, acc) -> [parse_stat(stat) | acc]
    end)
    |> Enum.reverse
  end

  @doc ~S"""

  """
  def retrieve(socket, mail)
  def retrieve(socket, {id, _size}),
    do: retrieve(socket, id)
  def retrieve(socket, id) do
    :ok = Socket.send(socket, "RETR #{id}\r\n")
    lines = receive_till(socket, ".")
    {:ok, tl(lines)}
  end

  @doc ~S"""

  """
  def delete(socket, mail)
  def delete(socket, {id, _size}),
    do: delete(socket, id)
  def delete(socket, id) do
    :ok = Socket.send(socket, "DELE #{id}\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  @doc ~S"""

  """
  def reset(socket) do
    :ok = Socket.send(socket, "RSET\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  @doc ~S"""

  """
  def quit(socket) do
    :ok = Socket.send(socket, "QUIT\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  defp login(socket, username, password) do
    with {:ok, _} <- recv(socket),
         {:ok, _} <- send_user(socket, username),
         {:ok, _} <- send_pass(socket, password),
      do: :ok
  end

  defp send_user(socket, username) do
    :ok = Socket.send(socket, "USER " <> username <> "\r\n")
    recv(socket)
  end

  defp send_pass(socket, password) do
    :ok = Socket.send(socket, "PASS " <> password <> "\r\n")
    recv(socket)
  end

  defp send_list(socket) do
    :ok = Socket.send(socket, "LIST\r\n")
    {:ok, receive_till(socket, ".")}
  end

  defp send_stat(socket) do
    :ok = Socket.send(socket, "STAT\r\n")
    recv(socket)
  end

  defp receive_till(socket, match, acc \\ [])
  defp receive_till(socket, match, acc) do
    {:ok, data} = Socket.recv(socket)
    check_if_end_of_stream(socket, match, data, acc)
  end

  defp check_if_end_of_stream(_socket, match, match, acc),
    do: Enum.reverse(acc)
  defp check_if_end_of_stream(socket, match, data, acc),
    do: receive_till(socket, match, [data | acc])

  defp parse_stat(data, count \\ "", size \\ nil)
  defp parse_stat("", count, size),
    do: {String.to_integer(count), String.to_integer(size)}
  defp parse_stat(" ", count, size),
    do: {String.to_integer(count), String.to_integer(size)}
  defp parse_stat(<<"\r", _rest :: binary>>, count, size),
    do: {String.to_integer(count), String.to_integer(size)}
  defp parse_stat(<<" ", rest :: binary>>, count, nil),
    do: parse_stat(rest, count, "")
  defp parse_stat(<<char :: binary-size(1), rest :: binary>>, count, nil),
      do: parse_stat(rest, count <> char, nil)
  defp parse_stat(<<char :: binary-size(1), rest :: binary>>, count, size),
    do: parse_stat(rest, count, size <> char)

  defp recv(socket) do
    {:ok, msg} = Socket.recv(socket)
    case msg do
      <<"+OK", msg :: binary>> ->
        {:ok, msg}
      <<"-ERR", reason :: binary>> ->
        {:error, String.strip(reason)}
    end
  end
end
