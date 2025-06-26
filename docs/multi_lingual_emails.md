# Handling Multi-lingual and Multi-encoded Emails

When working with multilingual emails from various sources (and different encodings, in particular from outlook), you may encounter messages in different languages and character encodings. 

Mailroom provides a way to handle these through the `:charset_handler` option.

## The Character Encoding Challenge

Email clients around the world use different character encodings to represent their text. Common encodings include:

- `windows-1252` (Western European)
- `iso-8859-1` (Latin-1)
- `us-ascii` (ASCII)
- `utf-8` (Unicode)
- And others

When processing these emails, you need to ensure that the character data is correctly converted to valid UTF-8. This avoids garbled text and/or processing errors.

## Configuring Charset Handling in Mailroom

Mailroom supports custom charset handling through the `:parser_opts` configuration and passes these to the mail library, which parses each part of the email. providing a`:charset_handler` function.

NOTE: Be sure to handle utf-8 and ascii text without encoding, and a fallback for unknown charsets. This is important to prevent processing errors.

### Example Implementation

Here's how you can implement charset handling in your Mailroom Inbox module:

```elixir
defmodule YourApp.ImapClient do
  use Mailroom.Inbox
  require Logger

  def config(_opts) do
    [
      ssl: true,
      folder: :inbox,
      username: "your_username",
      password: "your_password",
      server: "imap.example.com",
      ssl_opts: [verify: :verify_none],
      # charset_handler for each email part that specifies a charset
      parser_opts: [charset_handler: &handle_charset/2]
    ]
  end

  # Match and process emails as usual
  match do
    fetch_mail
    process(YourApp.ImapClient, :process_email)
  end


  def process_email(%Mailroom.Inbox.MessageContext{message: message}) do
    # process the email inject the message into your application
  end

  # Your charset handling functions - convert to utf-8 (elixir default)
  defp handle_charset("windows-1252", string),
    do: :unicode.characters_to_binary(string, :windows_1252, :utf8)

  defp handle_charset("iso-8859-1", string),
    do: :unicode.characters_to_binary(string, :latin1, :utf8)

  defp handle_charset("us-ascii", string),
    do: :unicode.characters_to_binary(string, :ascii, :utf8)

  # UTF-8 strings can pass through unchanged (elixir default)
  defp handle_charset("utf-8", string), do: string

  # FALLBACK: Handle unexpected charsets
  defp handle_charset(charset_name, string) do
    if String.valid?(string) do
      # If the string is valid (utf-8 compliant) then return as is
      string
    else
      Logger.error("Unexpected charset: #{charset_name} with an invalid string")
      # You can choose to raise an error or attempt a fallback conversion
      raise "Unexpected charset: #{charset_name} with an invalid string"
      # Alternatively, you could try a best-effort conversion maybe something like:
      # sanitize_utf8(string)
    end
  end
end
```

## How It Works

1. When an email is parsed, Mailroom extracts the charset information from the email headers
2. For each part of the email with a specified charset, Mailroom (passes `charset_handler` function) to mail library
3. Your handler function converts the string from the source encoding to UTF-8 (for each mail part)
4. The resulting UTF-8 string is used in the parsed email

For unexpected charsets, you have several options:

1. **Log and discard** - For non-critical applications
2. **Raise an error** - When correct encoding is essential
3. **Try sanitizing** - replace invalid characters with a placeholder

```elixir
  # something like this might be used to sanitize the string
  def sanitize_utf8(binary) do
    binary
      |> :unicode.characters_to_list(:utf8)
      |> case do
           {:error, valid_part, _invalid_part} -> valid_part
           valid_list when is_list(valid_list) -> valid_list
         end
      |> List.to_string()
    rescue
      _ -> binary |> :binary.bin_to_list() |> Enum.map(&safe_codepoint/1) |> List.to_string()
    end

    defp safe_codepoint(byte) when byte < 128, do: byte
    defp safe_codepoint(_), do: "?"  # Replace invalid bytes with question mark
```

## Handling Common Encodings

Erlang's `:unicode` module provides the `characters_to_binary/3` function which can convert between various encodings - see documentation [here](https://www.erlang.org/docs/28/apps/stdlib/unicode.html#characters_to_binary/1):

| Email Charset | Erlang Encoding Term |
|--------------|----------------------|
| windows-1252 | `:windows_1252`      |
| iso-8859-1   | `:latin1`            |
| us-ascii     | `:ascii`             |
| utf-8        | `:utf8`              |

For other encodings, you may need to use additional libraries or implement custom conversion logic.

## Testing Charset Handling

To test your charset handler implementation, you can send emails with all your expected/known encodings (subject and/or attachment) to your inbox.  Running these various emails through your application will help you ensure that the charset handler is handling the encoding as you expect.

## Conclusion

Properly handling character encodings is essential for working with international emails. By implementing a custom charset handler, you can ensure that email content is correctly converted to UTF-8, this allows `mailroom` and your application to handle multilingual and multi-encoded emails correctly.
