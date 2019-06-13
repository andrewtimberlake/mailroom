defmodule Mailroom.IMAP.BodyStructure do
  defmodule Part do
    defstruct section: nil,
              params: %{},
              multipart: false,
              type: nil,
              id: nil,
              description: nil,
              encoding: nil,
              encoded_size: nil,
              disposition: nil,
              file_name: nil,
              parts: []
  end

  @doc ~S"""
  Generates a `BodyStructure` struct from the IMAP ENVELOPE list
  """
  def new(list) do
    list
    |> build_structure
    |> number_sections
  end

  def has_attachment?(%Part{disposition: "attachment"}), do: true
  def has_attachment?(%Part{parts: []}), do: false
  def has_attachment?(%Part{parts: parts}), do: Enum.any?(parts, &has_attachment?/1)

  def get_attachments(body_structure, acc \\ [])
  def get_attachments(%Part{parts: []}, acc), do: Enum.reverse(acc)
  def get_attachments(%Part{parts: parts}, acc), do: get_attachments(parts, acc)

  def get_attachments([%Part{disposition: "attachment"} = part | tail], acc),
    do: get_attachments(tail, [part | acc])

  def get_attachments([], acc), do: Enum.reverse(acc)
  def get_attachments([_part | tail], acc), do: get_attachments(tail, acc)

  defp build_structure([[_ | _] | _rest] = list) do
    parse_multipart(list)
  end

  defp build_structure(list) do
    [type, sub_type, params, id, description, encoding, encoded_size | tail] = list

    %Part{
      type: String.downcase("#{type}/#{sub_type}"),
      params: parse_params(params),
      id: id,
      description: description,
      encoding: downcase(encoding),
      encoded_size: to_integer(encoded_size),
      disposition: parse_disposition(tail),
      file_name: parse_file_name(tail)
    }
  end

  defp parse_multipart(list, parts \\ [])

  defp parse_multipart([[_ | _] = part | rest], parts) do
    parse_multipart(rest, [part | parts])
  end

  defp parse_multipart([<<type::binary>> | _rest], parts) do
    parts = parts |> Enum.reverse() |> Enum.map(&build_structure/1)
    %Part{type: String.downcase(type), multipart: true, parts: parts}
  end

  defp parse_params(list, params \\ %{})
  defp parse_params(nil, params), do: params
  defp parse_params([], params), do: params

  defp parse_params([name, value | tail], params) do
    parse_params(tail, Map.put(params, String.downcase(name), value))
  end

  defp parse_disposition([]), do: nil
  defp parse_disposition([[disposition, [_ | _]] | _tail]), do: String.downcase(disposition)
  defp parse_disposition([_ | tail]), do: parse_disposition(tail)

  defp parse_file_name([]), do: nil
  defp parse_file_name([[_, [_ | _] = params] | _tail]), do: file_name_from_params(params)
  defp parse_file_name([_ | tail]), do: parse_file_name(tail)

  defp file_name_from_params(["FILENAME", file_name | _tail]), do: file_name
  defp file_name_from_params(["filename", file_name | _tail]), do: file_name
  defp file_name_from_params([_, _ | tail]), do: file_name_from_params(tail)

  defp number_sections(map, prefix \\ nil, section \\ nil)

  defp number_sections(map, prefix, section) do
    section = [prefix, section] |> Enum.filter(& &1) |> join(".")

    parts =
      map.parts
      |> Enum.with_index(1)
      |> Enum.map(fn {part, index} ->
        number_sections(part, section, index)
      end)

    %{map | section: section, parts: parts}
  end

  defp join([], _joiner), do: nil
  defp join(enum, joiner), do: Enum.join(enum, joiner)

  defp to_integer(nil), do: nil
  defp to_integer(string), do: String.to_integer(string)

  defp downcase(nil), do: nil
  defp downcase(string), do: String.downcase(string)
end
