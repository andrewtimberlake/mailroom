defmodule Mailroom.POP3 do
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
    {:ok, socket} = Socket.connect(server, opts.port, ssl: opts.ssl, debug: opts.debug)

    case login(socket, username, password) do
      :ok -> {:ok, socket}
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
    do: %{opts | port: 110}

  defp set_default_port(%{port: nil, ssl: true} = opts),
    do: %{opts | port: 995}

  defp set_default_port(opts),
    do: opts

  @doc """
  Sends the QUIT command and closes the connection

  ## Examples:

      #{inspect(__MODULE__)}.close(client)
      :ok
  """
  def close(socket) do
    quit(socket)
    Socket.close(socket)
  end

  @doc """
  Retrieves the number of available messages and the total size in octets

  ## Examples:

      #{inspect(__MODULE__)}.stat(client)
      {12, 13579}
  """
  def stat(socket) do
    {:ok, data} = send_stat(socket)
    parse_stat(String.strip(data))
  end

  @doc """
  Retrieves a list of all messages

  ## Examples:

      #{inspect(__MODULE__)}.list(client)
      [{1, 100}, {2, 200}]
  """
  def list(socket) do
    {:ok, data} = send_list(socket)

    data
    |> Enum.drop(1)
    |> Enum.reduce([], fn
      ".", acc -> acc
      stat, acc -> [parse_stat(stat) | acc]
    end)
    |> Enum.reverse()
  end

  @doc """
  Retrieves a message.

  ## Examples:

      > #{inspect(__MODULE__)}.retrieve(client, {1, 100})
      ["Date: Fri, 30 Sep 2016 10:48:00 +0200", "Subject: Test message", "To: user@example.com", "", "Test message"]
      > #{inspect(__MODULE__)}.retrieve(client, 1)
      ["Date: Fri, 30 Sep 2016 10:48:00 +0200", "Subject: Test message", "To: user@example.com", "", "Test message"]
  """
  def retrieve(socket, mail)

  def retrieve(socket, {id, _size}),
    do: retrieve(socket, id)

  def retrieve(socket, id) do
    :ok = Socket.send(socket, "RETR #{id}\r\n")
    lines = receive_till(socket, ".")
    {:ok, tl(lines)}
  end

  @doc """
  Marks a message for deletion.

  ## Examples:

      > #{inspect(__MODULE__)}.delete(client, {1, 100})
      :ok
      > #{inspect(__MODULE__)}.delete(client, 1)
      :ok
  """
  def delete(socket, mail)

  def delete(socket, {id, _size}),
    do: delete(socket, id)

  def delete(socket, id) do
    :ok = Socket.send(socket, "DELE #{id}\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  @doc """
  Resets all messages marked for deletion.

  ## Examples:

      > #{inspect(__MODULE__)}.reset(client)
      :ok
  """
  def reset(socket) do
    :ok = Socket.send(socket, "RSET\r\n")
    {:ok, _} = recv(socket)
    :ok
  end

  @doc """
  Sends the QUIT command to end the transaction.

  ## Examples:

      > #{inspect(__MODULE__)}.reset(client)
      :ok
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

  defp parse_stat(<<"\r", _rest::binary>>, count, size),
    do: {String.to_integer(count), String.to_integer(size)}

  defp parse_stat(<<" ", rest::binary>>, count, nil),
    do: parse_stat(rest, count, "")

  defp parse_stat(<<char::binary-size(1), rest::binary>>, count, nil),
    do: parse_stat(rest, count <> char, nil)

  defp parse_stat(<<char::binary-size(1), rest::binary>>, count, size),
    do: parse_stat(rest, count, size <> char)

  defp recv(socket) do
    {:ok, msg} = Socket.recv(socket)

    case msg do
      <<"+OK", msg::binary>> ->
        {:ok, msg}

      <<"-ERR", reason::binary>> ->
        {:error, String.strip(reason)}
    end
  end
end
