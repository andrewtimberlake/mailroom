# Mailroom

Send, receive and process emails.

## Example:

### POP3
```elixir
alias Mailroom.POP3

{:ok, client} = POP3.connect(server, username, password, port: port, ssl: true)
client
|> POP3.list
|> Enum.each(fn(mail) ->
  {:ok, message} = POP3.retrieve(client, mail)
  # process message
  :ok = POP3.delete(client, mail)
end)
:ok = POP3.reset(client)
:ok = POP3.close(client)
```

### SMTP
```elixir
  alias Mailroom.SMTP
  alias Mailroom.SMTP.Email
  
  def config, do:
    [
      username: System.get_env("EMAIL_USER"),
      password: System.get_env("EMAIL_PASS"),
      port: 587
    ]
  
  def test_email() do
    {:ok, client} = SMTP.connect("smtp.example.com", config()) 

    Email.new()
    |> Email.from("user1@example.com")
    |> Email.to(["user2@example.com", "user3@example.com"])
    |> Email.subject("This is only a test")
    |> Email.message("Write your message here!!!")
    |> SMTP.send(client)

    SMTP.quit(client)
  end
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `mailroom` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:mailroom, "~> 0.0.1"}]
    end
    ```

  2. Ensure `mailroom` is started before your application:

    ```elixir
    def application do
      [applications: [:mailroom]]
    end
    ```
