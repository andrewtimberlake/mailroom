defmodule Mailroom.POP3Test do
  use ExUnit.Case
  doctest Mailroom.POP3

  alias Mailroom.POP3

  test "connect" do
    server   = Application.get_env(:mailroom, :pop3_server)
    port     = Application.get_env(:mailroom, :pop3_port)
    username = Application.get_env(:mailroom, :pop3_username)
    password = Application.get_env(:mailroom, :pop3_password)
    ssl      = Application.get_env(:mailroom, :pop3_ssl, false)

    {:ok, client} = POP3.connect(server, username, password, port: port, ssl: ssl)
    IO.inspect(POP3.stat(client))
    POP3.each_mail(client, fn(mail) ->
      IO.inspect(mail)
      {:ok, message} = POP3.retrieve(client, mail)
      IO.puts(message)
      :ok = POP3.delete(client, mail)
    end)
    :ok = POP3.reset(client)
    :ok = POP3.close(client)
  end
end
