defmodule Mailroom.IMAP.Envelope do
  defstruct ~w[date subject from sender reply_to to cc bcc in_reply_to message_id]a

  defmodule Address do
    defstruct ~w[name mailbox_name host_name email]a

    def new(name, mailbox_name, host_name) do
      %__MODULE__{
        name: name,
        mailbox_name: mailbox_name,
        host_name: host_name,
        email: join_email(mailbox_name, host_name)
      }
    end

    defp join_email(mailbox_name, host_name) do
      [mailbox_name, host_name]
      |> Enum.filter(& &1)
      |> Enum.join("@")
    end

    def normalize(nil), do: nil
    def normalize([]), do: []

    def normalize(%__MODULE__{} = address) do
      %{name: name, mailbox_name: mailbox_name, host_name: host_name} = address
      new(downcase(name), downcase(mailbox_name), downcase(host_name))
    end

    def normalize([address | tail]), do: [normalize(address) | normalize(tail)]

    defp downcase(nil), do: nil
    defp downcase(string), do: String.downcase(string)
  end

  @doc ~S"""
  Generates an `Envelope` struct from the IMAP ENVELOPE list
  """
  def new(list) do
    [date, subject, from, sender, reply_to, to, cc, bcc, in_reply_to, message_id] = list

    date = Mail.Parsers.RFC2822.erl_from_timestamp(date)
    from = parse_addresses(from)
    sender = parse_addresses(sender)
    reply_to = parse_addresses(reply_to)
    to = parse_addresses(to)
    cc = parse_addresses(cc)
    bcc = parse_addresses(bcc)

    %__MODULE__{
      date: date,
      subject: subject,
      from: from,
      sender: sender,
      reply_to: reply_to,
      to: to,
      cc: cc,
      bcc: bcc,
      in_reply_to: in_reply_to,
      message_id: message_id
    }
  end

  def normalize(%__MODULE__{} = envelope) do
    %{
      from: from,
      sender: sender,
      reply_to: reply_to,
      to: to,
      cc: cc,
      bcc: bcc,
      in_reply_to: in_reply_to,
      message_id: message_id
    } = envelope

    %{
      envelope
      | from: Address.normalize(from),
        sender: Address.normalize(sender),
        reply_to: Address.normalize(reply_to),
        to: Address.normalize(to),
        cc: Address.normalize(cc),
        bcc: Address.normalize(bcc),
        in_reply_to: downcase(in_reply_to),
        message_id: downcase(message_id)
    }
  end

  defp downcase(nil), do: nil
  defp downcase(string), do: String.downcase(string)

  defp parse_addresses(nil), do: []
  defp parse_addresses([]), do: []

  defp parse_addresses(values) do
    Enum.map(values, fn [name, _smtp_source_route, mailbox_name, host_name] ->
      Address.new(name, mailbox_name, host_name)
    end)
  end
end
