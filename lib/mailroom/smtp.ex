defmodule Mailroom.SMTP do
  alias Mailroom.Socket

  def connect(server, options \\ []) do
    port = Keyword.get(options, :port, 25)
    {:ok, socket} = Socket.connect(server, port, options)
    case handshake(socket) do
      :ok -> {:ok, socket}
      {:ok, extensions} ->
        if Enum.find(extensions, fn(el) -> el == "STARTTLS" end) do
          do_starttls(socket)
        else
          {:ok, socket}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  def send_message(socket, from, to, message) do
    Socket.send(socket, ["MAIL FROM: <", from, ">\r\n"])
    {:ok, data} = Socket.recv(socket)
    {250, _ok} = parse_smtp_response(data)

    Socket.send(socket, ["RCPT TO: <", to, ">\r\n"])
    {:ok, data} = Socket.recv(socket)
    {250, _ok} = parse_smtp_response(data)

    Socket.send(socket, "DATA\r\n")
    {:ok, data} = Socket.recv(socket)
    {354, _ok} = parse_smtp_response(data)

    message
    |> String.split(~r/\r\n/)
    |> Enum.each(fn(line) ->
      :ok = Socket.send(socket, [line, "\r\n"])
    end)

    :ok = Socket.send(socket, ".\r\n")
    {:ok, data} = Socket.recv(socket)
    {250, _ok} = parse_smtp_response(data)
    :ok
  end

  def quit(socket) do
    Socket.send(socket, "QUIT\r\n")
    {:ok, data} = Socket.recv(socket)
    {221, _message} = parse_smtp_response(data)
  end

  defp handshake(socket) do
    {:ok, data} = Socket.recv(socket)
    {220, _message} = parse_smtp_response(data)
    case try_ehlo(socket) do
      {:ok, extensions} ->
        extensions = Enum.map(extensions, fn({_code, extension}) -> extension end)
        {:ok, extensions}
      {:error, _reason} ->
        try_helo(socket)
    end
  end

  defp try_ehlo(socket) do
    Socket.send(socket, ["EHLO ", fqdn, "\r\n"])
    recv_ehlo_response(socket)
  end

  defp try_helo(socket) do
    Socket.send(socket, ["HELO ", fqdn, "\r\n"])
    {:ok, data} = Socket.recv(socket)
    {250, _message} = parse_smtp_response(data)
    :ok
  end

  defp do_starttls(socket) do
    Socket.send(socket, "STARTTLS\r\n")
    {:ok, data} = Socket.recv(socket)
    {220, _message} = parse_smtp_response(data)
    {:ok, socket} = Socket.ssl_client(socket)
    {:ok, extensions} = try_ehlo(socket)
    {:ok, socket}
  end

  defp parse_smtp_response(data) do
    [code, message] = String.split(data, " ", parts: 2)
    # |> IO.inspect
    {String.to_integer(code), message}
  end

  defp recv_ehlo_response(socket, acc \\ [])
  defp recv_ehlo_response(socket, acc) do
    {:ok, data} = Socket.recv(socket)
    process_ehlo_line(socket, data, acc)
  end

  defp process_ehlo_line(_socket, <<"500", " ", rest :: binary>>, _acc),
    do: {:error, rest}
  defp process_ehlo_line(socket, <<"250", "-", rest :: binary>>, acc),
    do: recv_ehlo_response(socket, [parse_smtp_response("250 " <> rest) | acc])
  defp process_ehlo_line(_socket, <<"250", " ", rest :: binary>>, acc),
    do: {:ok, Enum.reverse([parse_smtp_response("250 " <> rest) | acc])}

  def fqdn do
    {:ok, name} = :inet.gethostname
    {:ok, hostent} = :inet.gethostbyname(name)
    {:hostent, fqdn, _aliases, :inet, _, _addresses} = hostent
    to_string(fqdn)
  end
end
