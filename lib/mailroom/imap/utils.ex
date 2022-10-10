defmodule Mailroom.IMAP.Utils do
  @moduledoc false

  @type item :: String.t() | atom

  @spec parse_list_only(String.t()) :: iolist
  def parse_list_only(string) do
    {list, _rest} = parse_list(string)
    list
  end

  @spec parse_list(String.t(), non_neg_integer, String.t() | nil, iolist | nil) ::
          {iolist, String.t()}
  def parse_list(string, depth \\ 0, temp \\ nil, acc \\ nil)

  def parse_list(<<"(", rest::binary>>, depth, _temp, acc) do
    {list, rest} = parse_list(rest, depth + 1, nil, [])
    acc = if acc, do: [list | acc], else: list

    if depth == 0 do
      {acc, rest}
    else
      parse_list(rest, depth, nil, acc)
    end
  end

  def parse_list(<<")", rest::binary>>, _depth, temp, acc),
    do: {Enum.reverse(prepend_to_list(acc, temp)), rest}

  def parse_list(<<"\"", _rest::binary>> = string, depth, _temp, acc) do
    {string, rest} = parse_string(string)
    parse_list(rest, depth, string, acc)
  end

  def parse_list(<<"{", rest::binary>>, depth, _temp, acc) do
    {octets, <<"\r\n", rest::binary>>} = read_until(rest, "}")
    octets = String.to_integer(octets)
    <<string::binary-size(octets), rest::binary>> = rest
    parse_list(rest, depth, nil, prepend_to_list(acc, string))
  end

  def parse_list(<<" ", rest::binary>>, depth, nil, acc),
    do: parse_list(rest, depth, nil, acc)

  def parse_list(<<"\r", rest::binary>>, depth, temp, acc),
    do: parse_list(rest, depth, "\r", prepend_to_list(acc, temp))

  def parse_list(<<" ", rest::binary>>, depth, temp, acc),
    do: parse_list(rest, depth, nil, prepend_to_list(acc, temp))

  def parse_list(<<char::utf8, rest::binary>>, depth, nil, acc),
    do: parse_list(rest, depth, <<char>>, acc)

  def parse_list(<<char::utf8, rest::binary>>, depth, temp, acc),
    do: parse_list(rest, depth, <<temp::binary, char>>, acc)

  @spec prepend_to_list(list | nil, any) :: list
  defp prepend_to_list(nil, item), do: List.wrap(item)
  defp prepend_to_list(list, nil), do: list
  defp prepend_to_list(nil, "NIL"), do: [nil]
  defp prepend_to_list(list, "NIL"), do: [nil | list]
  defp prepend_to_list(list, item), do: [item | list]

  @spec parse_string_only(String.t()) :: String.t()
  def parse_string_only(string) do
    {string, _} = parse_string(string)
    string
  end

  @spec read_until(binary, binary) :: {binary, binary}
  defp read_until(string, char, acc \\ [])

  defp read_until(<<until, rest::binary>>, <<until>>, acc),
    do: {:erlang.iolist_to_binary(Enum.reverse(acc)), rest}

  defp read_until(<<char, rest::binary>>, until, acc),
    do: read_until(rest, until, [char | acc])

  @spec parse_string(String.t()) :: {String.t(), String.t()}
  def parse_string(string),
    do: do_parse_string(String.next_grapheme(string), false, [])

  @spec do_parse_string({String.t(), String.t()} | nil, boolean, iodata) ::
          {String.t(), String.t()}
  defp do_parse_string({"\\", rest}, inquotes, acc) do
    {grapheme, rest} = String.next_grapheme(rest)
    do_parse_string(String.next_grapheme(rest), inquotes, [grapheme | acc])
  end

  defp do_parse_string({"\"", rest}, false, acc),
    do: do_parse_string(String.next_grapheme(rest), true, acc)

  defp do_parse_string({"\"", rest}, true, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp do_parse_string({" ", rest}, false, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), <<" ", rest::binary>>}

  defp do_parse_string({"\r\n", rest}, false, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), <<"\r\n", rest::binary>>}

  defp do_parse_string({nil, rest}, false, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), <<" ", rest::binary>>}

  defp do_parse_string({grapheme, rest}, inquotes, acc),
    do: do_parse_string(String.next_grapheme(rest), inquotes, [grapheme | acc])

  @spec items_to_list(item | [item]) :: [String.t()]
  def items_to_list(list, acc \\ [])

  def items_to_list([], [" " | acc]),
    do: Enum.reverse([")" | acc])

  def items_to_list(list, []),
    do: items_to_list(list, ["("])

  def items_to_list([head | tail], acc),
    do: items_to_list(tail, [" ", item_to_string(head) | acc])

  def items_to_list(non_list, acc),
    do: items_to_list(List.wrap(non_list), acc)

  @spec item_to_string(item) :: String.t()
  defp item_to_string(string) when is_binary(string), do: string

  [
    # STATUS
    messages: "MESSAGES",
    recent: "RECENT",
    unseen: "UNSEEN",
    uid_next: "UIDNEXT",
    uid_validity: "UIDVALIDITY",
    # FETCH
    all: "ALL",
    answered: "ANSWERED",
    fast: "FAST",
    full: "FULL",
    body: "BODY",
    # "BODY[<section>]<<partial>>",
    # "BODY.PEEK[<section>]<<partial>>",
    body_structure: "BODYSTRUCTURE",
    envelope: "ENVELOPE",
    flags: "FLAGS",
    internal_date: "INTERNALDATE",
    rfc822: "RFC822",
    rfc822_header: "RFC822.HEADER",
    rfc822_size: "RFC822.SIZE",
    rfc822_text: "RFC822.TEXT",
    uid: "UID",
    header: "BODY.PEEK[HEADER]"
  ]
  |> Enum.each(fn {atom, string} ->
    defp item_to_string(unquote(atom)), do: unquote(string)
    defp item_to_atom(unquote(string)), do: unquote(atom)
  end)

  @spec item_to_atom(item) :: item
  defp item_to_atom(string), do: string

  @type item_map(val) :: %{optional(atom) => val, optional(String.t()) => val}

  @spec list_to_items(iolist) :: item_map(iodata)
  def list_to_items(list, acc \\ %{})
  def list_to_items([], acc), do: acc

  def list_to_items([item, value | tail], acc),
    do: list_to_items(tail, Map.put_new(acc, item_to_atom(item), value))

  @spec list_to_status_items(iolist) :: item_map(non_neg_integer)
  def list_to_status_items(list, acc \\ %{})
  def list_to_status_items([], acc), do: acc

  def list_to_status_items([item, count | tail], acc),
    do: list_to_status_items(tail, Map.put_new(acc, item_to_atom(item), parse_number(count)))

  @spec flags_to_list(item | [item]) :: [String.t()]
  def flags_to_list(list, acc \\ [])

  def flags_to_list([], []), do: []

  def flags_to_list([], [" " | acc]),
    do: Enum.reverse([")" | acc])

  def flags_to_list(list, []),
    do: flags_to_list(list, ["("])

  def flags_to_list([head | tail], acc),
    do: flags_to_list(tail, [" ", flag_to_string(head) | acc])

  def flags_to_list(non_list, acc),
    do: flags_to_list(List.wrap(non_list), acc)

  @spec flag_to_string(item) :: String.t()
  defp flag_to_string(string) when is_binary(string), do: string

  [
    seen: "\\Seen",
    answered: "\\Answered",
    flagged: "\\Flagged",
    deleted: "\\Deleted",
    draft: "\\Draft",
    recent: "\\Recent"
  ]
  |> Enum.each(fn {atom, string} ->
    defp flag_to_string(unquote(atom)), do: unquote(string)
    defp flag_to_atom(unquote(string)), do: unquote(atom)
  end)

  @spec flag_to_atom(String.t()) :: item
  defp flag_to_atom(string), do: string

  @spec list_to_flags([String.t()]) :: [item]
  def list_to_flags(list),
    do: Enum.map(list, &flag_to_atom/1)

  @spec parse_number(String.t()) :: non_neg_integer
  def parse_number(string, acc \\ "")

  0..9
  |> Enum.map(&Integer.to_string/1)
  |> Enum.each(fn digit ->
    def parse_number(<<unquote(digit), rest::binary>>, acc),
      do: parse_number(rest, <<acc::binary, unquote(digit)>>)
  end)

  def parse_number(_, acc),
    do: String.to_integer(acc)

  @spec parse_timestamp(String.t()) :: :calendar.datetime()
  def parse_timestamp(
        <<date::binary-size(2), "-", month::binary-size(3), "-", year::binary-size(4), " ",
          hour::binary-size(2), ":", minute::binary-size(2), ":", second::binary-size(2), " ",
          timezone::binary-size(3), _rest::binary>>
      ) do
    Mail.Parsers.RFC2822.erl_from_timestamp(
      date <>
        " " <>
        month <>
        " " <> year <> " " <> hour <> ":" <> minute <> ":" <> second <> " (" <> timezone <> ")"
    )
  end

  @spec quote_string(String.t()) :: String.t()
  def quote_string(string),
    do: do_quote_string(String.next_grapheme(string), ["\""])

  @spec do_quote_string({String.t(), String.t()} | nil, iodata) :: String.t()
  defp do_quote_string({"\"", rest}, acc),
    do: do_quote_string(String.next_grapheme(rest), ["\\\"" | acc])

  defp do_quote_string({grapheme, rest}, acc),
    do: do_quote_string(String.next_grapheme(rest), [grapheme | acc])

  defp do_quote_string(nil, acc),
    do: IO.iodata_to_binary(Enum.reverse(["\"" | acc]))

  @type sequence :: Range.t() | integer

  @spec numbers_to_sequences([integer]) :: [sequence]
  def numbers_to_sequences([]), do: []

  def numbers_to_sequences(list) do
    list
    |> Enum.sort()
    |> Enum.uniq()
    |> do_numbers_to_sequences(nil, [])
  end

  @spec do_numbers_to_sequences([integer], sequence | nil, [sequence]) :: [sequence]
  defp do_numbers_to_sequences([], temp, acc),
    do: [temp | acc] |> Enum.reverse()

  defp do_numbers_to_sequences([number | tail], nil, acc),
    do: do_numbers_to_sequences(tail, number, acc)

  defp do_numbers_to_sequences([number | tail], temp, acc) when number - 1 == temp,
    do: do_numbers_to_sequences(tail, temp..number, acc)

  defp do_numbers_to_sequences([number | tail], %Range{first: first, last: last}, acc)
       when number - 1 == last,
       do: do_numbers_to_sequences(tail, first..number, acc)

  defp do_numbers_to_sequences(list, temp, acc),
    do: do_numbers_to_sequences(list, nil, [temp | acc])
end
