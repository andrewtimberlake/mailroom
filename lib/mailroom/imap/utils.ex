defmodule Mailroom.IMAP.Utils do

  def parse_list(string) do
    {list, _str} = do_parse_list(string)
    list
  end

  defp do_parse_list(string, temp \\ nil, acc \\ [])

  defp do_parse_list(<<"[", rest :: binary>>, temp, []),
    do: do_parse_list(rest, temp, [])
  defp do_parse_list(<<"[", _rest :: binary>> = string, _temp, acc) do
    {list, rest} = do_parse_list(string, nil, [])
    do_parse_list(rest, nil, [list | acc])
  end
  defp do_parse_list(<<"]", rest :: binary>>, nil, acc),
    do: {Enum.reverse(acc), rest}
  defp do_parse_list(<<"]", rest :: binary>>, temp, acc),
    do: {Enum.reverse([temp | acc]), rest}

  defp do_parse_list(<<"(", rest :: binary>>, temp, []),
    do: do_parse_list(rest, temp, [])
  defp do_parse_list(<<"(", _rest :: binary>> = string, _temp, acc) do
    {list, rest} = do_parse_list(string, nil, [])
    do_parse_list(rest, nil, [list | acc])
  end
  defp do_parse_list(<<")", rest :: binary>>, nil, acc),
    do: {Enum.reverse(acc), rest}
  defp do_parse_list(<<")", rest :: binary>>, temp, acc),
    do: {Enum.reverse([temp | acc]), rest}

  defp do_parse_list(<<"\r", rest :: binary>>, nil, acc),
    do: {Enum.reverse(acc), rest}
  defp do_parse_list(<<"\r", rest :: binary>>, temp, acc),
    do: {Enum.reverse([temp | acc]), rest}

  defp do_parse_list(<<" ", rest :: binary>>, nil, acc),
    do: do_parse_list(rest, nil, acc)
  defp do_parse_list(<<" ", rest :: binary>>, temp, acc),
    do: do_parse_list(rest, nil, [temp | acc])
  defp do_parse_list(<<char :: utf8, rest :: binary>>, nil, acc),
    do: do_parse_list(rest, <<char>>, acc)
  defp do_parse_list(<<char :: utf8, rest :: binary>>, temp, acc),
    do: do_parse_list(rest, <<temp :: binary, char>>, acc)

  def parse_number(string, acc \\ "")
  0..9
  |> Enum.map(&Integer.to_string/1)
  |> Enum.each(fn(digit) ->
    def parse_number(<<unquote(digit), rest :: binary>>, acc),
      do: parse_number(rest, <<acc :: binary, unquote(digit)>>)
  end)
  def parse_number(_, acc),
    do: String.to_integer(acc)
end
