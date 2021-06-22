defmodule ArchEthicWeb.GraphQLSchema.ContentType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Content] scalar type represents transaction content. Depending if the content can displayed
  it will be rendered as plain text otherwise in hexadecimal
  """
  scalar :content do
    serialize(&Base.encode16/1)
  end

  def serialize(content) do
    if String.printable?(content) do
      content
    else
      Base.encode16(content)
    end
  end
end
