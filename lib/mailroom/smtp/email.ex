defmodule Mailroom.SMTP.Email do
  defstruct from: "",
            to: [],
            cc: [],
            subject: "",
            message: ""

  def new(), do: %__MODULE__{}

  def from(email, from), do: Map.put(email, :from, from)

  def to(email, to) when is_bitstring(to), do: Map.put(email, :to, [to])
  def to(email, to) when is_list(to), do: Map.put(email, :to, to)

  def cc(email, cc) when is_bitstring(cc), do: Map.put(email, :cc, [cc])
  def cc(email, cc) when is_list(cc), do: Map.put(email, :cc, cc)

  def subject(email, subject), do: Map.put(email, :subject, subject)

  def message(email, message), do: Map.put(email, :message, message)
end
