defmodule Mailroom.IMAP.Utils do

  def parse_list_only(string) do
    {list, _} = parse_list(string)
    list
  end

  def parse_list(string, temp \\ nil, acc \\ [])

  def parse_list(<<"[", rest :: binary>>, temp, []),
    do: parse_list(rest, temp, [])
  def parse_list(<<"[", _rest :: binary>> = string, _temp, acc) do
    {list, rest} = parse_list(string, nil, [])
    parse_list(rest, nil, [list | acc])
  end
  def parse_list(<<"]", rest :: binary>>, nil, acc),
    do: {Enum.reverse(acc), rest}
  def parse_list(<<"]", rest :: binary>>, temp, acc),
    do: {Enum.reverse([temp | acc]), rest}

  def parse_list(<<"(", rest :: binary>>, temp, []),
    do: parse_list(rest, temp, [])
  def parse_list(<<"(", _rest :: binary>> = string, _temp, acc) do
    {list, rest} = parse_list(string, nil, [])
    parse_list(rest, nil, [list | acc])
  end
  def parse_list(<<")", rest :: binary>>, nil, acc),
    do: {Enum.reverse(acc), rest}
  def parse_list(<<")", rest :: binary>>, temp, acc),
    do: {Enum.reverse([temp | acc]), rest}

  def parse_list(<<"\r", _rest :: binary>> = string, nil, acc),
    do: {Enum.reverse(acc), string}
  def parse_list(<<"\r", _rest :: binary>> = string, temp, acc),
    do: {Enum.reverse([temp | acc]), string}

  def parse_list(<<" ", rest :: binary>>, nil, acc),
    do: parse_list(rest, nil, acc)
  def parse_list(<<" ", rest :: binary>>, temp, acc),
    do: parse_list(rest, nil, [temp | acc])
  def parse_list(<<char :: utf8, rest :: binary>>, nil, acc),
    do: parse_list(rest, <<char>>, acc)
  def parse_list(<<char :: utf8, rest :: binary>>, temp, acc),
    do: parse_list(rest, <<temp :: binary, char>>, acc)

  def parse_string_only(string) do
    {string, _} = parse_string(string)
    string
  end

  def parse_string(string),
    do: do_parse_string(String.next_grapheme(string), false, [])

  defp do_parse_string({"\\", rest}, inquotes, acc) do
    {grapheme, rest} = String.next_grapheme(rest)
    do_parse_string(String.next_grapheme(rest), inquotes, [grapheme | acc])
  end
  defp do_parse_string({"\"", rest}, false, acc),
    do: do_parse_string(String.next_grapheme(rest), true, acc)
  defp do_parse_string({"\"", rest}, true, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp do_parse_string({" ", rest}, false, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), <<" ", rest :: binary>>}
  defp do_parse_string({"\r\n", rest}, false, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), <<"\r\n", rest :: binary>>}
  defp do_parse_string({nil, rest}, false, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), <<" ", rest :: binary>>}

  defp do_parse_string({grapheme, rest}, inquotes, acc),
    do: do_parse_string(String.next_grapheme(rest), inquotes, [grapheme | acc])

  def parse_number(string, acc \\ "")
  0..9
  |> Enum.map(&Integer.to_string/1)
  |> Enum.each(fn(digit) ->
    def parse_number(<<unquote(digit), rest :: binary>>, acc),
      do: parse_number(rest, <<acc :: binary, unquote(digit)>>)
  end)
  def parse_number(_, acc),
    do: String.to_integer(acc)

  def quote_string(string),
    do: do_quote_string(String.next_grapheme(string), ["\""])

  defp do_quote_string({"\"", rest}, acc),
    do: do_quote_string(String.next_grapheme(rest), ["\\\"" | acc])
  defp do_quote_string({grapheme, rest}, acc),
    do: do_quote_string(String.next_grapheme(rest), [grapheme | acc])
  defp do_quote_string(nil, acc),
    do: IO.iodata_to_binary(Enum.reverse(["\"" | acc]))
end
