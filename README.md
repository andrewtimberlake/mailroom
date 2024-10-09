# Mailroom

Send, receive and process emails.

## Example:

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

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

1. Add `mailroom` to your list of dependencies in `mix.exs`:

   ```elixir
   def deps do
     [{:mailroom, "~> 0.5.0"}]
   end
   ```

2. Ensure `mailroom` is started before your application:

   ```elixir
   def application do
     [applications: [:mailroom]]
   end
   ```
