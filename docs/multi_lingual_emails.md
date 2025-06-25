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

When processing these emails, you need to ensure that the character data is correctly converted to a consistent encoding (typically UTF-8) to avoid garbled text or processing errors.

## Configuring Charset Handling in Mailroom

Mailroom supports custom charset handling through the `:parser_opts` configuration. You can provide a `:charset_handler` function that will be called with the charset name and the string to convert.

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

  # Handle unexpected charsets
  defp handle_charset(charset_name, string) do
    if String.valid?(string) do
      # If the string is valid (utf-8 compliant) then return as is
      string
    else
      Logger.error("Unexpected charset: #{charset_name} with an invalid string")
      # You can choose to raise an error or attempt a fallback conversion
      raise "Unexpected charset: #{charset_name} with an invalid string"
      # Alternatively, you could try a best-effort conversion:
      # :unicode.characters_to_binary(string, :latin1, :utf8)
    end
  end
end
```

## How It Works

1. When an email is parsed, Mailroom extracts the charset information from the email headers
2. For each part of the email with a specified charset, Mailroom (passes `charset_handler` function) to mail library
3. Your handler function converts the string from the source encoding to UTF-8 (for each mail part)
4. The resulting UTF-8 string is used in the parsed email

## Handling Common Encodings

Erlang's `:unicode` module provides the `characters_to_binary/3` function which can convert between various encodings - see documentation [here](https://www.erlang.org/docs/28/apps/stdlib/unicode.html#characters_to_binary/1):

| Email Charset | Erlang Encoding Term |
|--------------|----------------------|
| windows-1252 | `:windows_1252`      |
| iso-8859-1   | `:latin1`            |
| us-ascii     | `:ascii`             |
| utf-8        | `:utf8`              |

For other encodings, you may need to use additional libraries or implement custom conversion logic.

## Fallback Strategies

For unexpected charsets, you have several options:

1. **Pass through the string unchanged** - Works if the string is actually valid UTF-8
2. **Try a common encoding** - Often `:latin1` can work as a reasonable fallback
3. **Log and discard** - For non-critical applications
4. **Raise an error** - When correct encoding is essential

## Testing Charset Handling

To test your charset handler implementation, you can create test emails with different encodings.  Office365 (latin1 encoding in subject and filenames), outlook configured to use utf-8 (subject and filenames) and mac and windows client to use utf-8 (subject and filenames).

## Conclusion

Properly handling character encodings is essential for working with international emails. By implementing a custom charset handler, you can ensure that email content is correctly converted to UTF-8, this allows mailroom and your application to handle multilingual and multi-encoded emails correctly.
