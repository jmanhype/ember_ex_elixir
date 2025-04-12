defmodule EmberEx.Examples.Schemas do
  @moduledoc """
  Example schemas for the EmberEx examples.
  
  This module defines Ecto schemas for various example use cases.
  """
end

# Schema for text summarization input
defmodule EmberEx.Examples.Schemas.SummarizeInput do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :text, :string
    field :max_length, :integer, default: 100
  end
  
  def changeset(input, attrs) do
    input
    |> cast(attrs, [:text, :max_length])
    |> validate_required([:text])
  end
end

# Schema for text summarization output
defmodule EmberEx.Examples.Schemas.SummarizeOutput do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :summary, :string
  end
  
  def changeset(output, attrs) do
    output
    |> cast(attrs, [:summary])
    |> validate_required([:summary])
  end
end

# Schema for question answering input
defmodule EmberEx.Examples.Schemas.QAInput do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :question, :string
    field :context, :string
  end
  
  def changeset(input, attrs) do
    input
    |> cast(attrs, [:question, :context])
    |> validate_required([:question, :context])
  end
end

# Schema for question answering output
defmodule EmberEx.Examples.Schemas.QAOutput do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :answer, :string
    field :confidence, :float, default: 0.0
  end
  
  def changeset(output, attrs) do
    output
    |> cast(attrs, [:answer, :confidence])
    |> validate_required([:answer])
  end
end

# Schema for translation input
defmodule EmberEx.Examples.Schemas.TranslateInput do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :text, :string
    field :source_language, :string, default: "auto"
    field :target_language, :string
  end
  
  def changeset(input, attrs) do
    input
    |> cast(attrs, [:text, :source_language, :target_language])
    |> validate_required([:text, :target_language])
  end
end

# Schema for translation output
defmodule EmberEx.Examples.Schemas.TranslateOutput do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :translated_text, :string
    field :detected_language, :string
  end
  
  def changeset(output, attrs) do
    output
    |> cast(attrs, [:translated_text, :detected_language])
    |> validate_required([:translated_text])
  end
end
