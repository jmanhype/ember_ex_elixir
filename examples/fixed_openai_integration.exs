#!/usr/bin/env elixir
# Fixed example demonstrating OpenAI integration with EmberEx
#
# This example shows how to:
# 1. Configure EmberEx to use OpenAI
# 2. Create and use simple LLM operators
# 3. Create operators with structured output
# 4. Compose LLM operators together

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.FixedOpenAIIntegration do
  @moduledoc """
  Fixed example demonstrating OpenAI integration with EmberEx.
  
  Shows various ways to interact with OpenAI models through EmberEx's
  operator system with proper schema definitions.
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator}

  # Define Ecto schemas for structured outputs
  defmodule PoemSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :poem, :string
    end

    def changeset(schema, params) do
      schema
      |> cast(params, [:poem])
      |> validate_required([:poem])
    end
  end

  defmodule AnalysisSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :sentiment, :string
      field :score, :float
      field :themes, {:array, :string}
      field :summary, :string
    end

    def changeset(schema, params) do
      schema
      |> cast(params, [:sentiment, :score, :themes, :summary])
      |> validate_required([:sentiment, :score, :themes, :summary])
      |> validate_inclusion(:sentiment, ["positive", "negative", "neutral"])
      |> validate_number(:score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    end
  end

  defmodule IdeaSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :ideas, :string
    end

    def changeset(schema, params) do
      schema
      |> cast(params, [:ideas])
      |> validate_required([:ideas])
    end
  end

  defmodule RankedIdeaSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :idea, :string
      field :score, :integer
      field :reasoning, :string
    end

    def changeset(schema, params) do
      schema
      |> cast(params, [:idea, :score, :reasoning])
      |> validate_required([:idea, :score, :reasoning])
      |> validate_number(:score, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    end
  end

  defmodule RankedIdeasSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      embeds_many :ranked_ideas, RankedIdeaSchema
    end

    def changeset(schema, params) do
      schema
      |> cast(params, [])
      |> cast_embed(:ranked_ideas, required: true)
    end
  end
  
  @doc """
  Run the example.
  """
  def run do
    IO.puts("=== EmberEx Fixed OpenAI Integration Example ===\n")
    
    # Set up API key from environment variable or directly using the key value
    # Note: Using environment variables is more secure than hardcoding the key
    setup_api_key()
    
    # Example 1: Basic LLM operator using custom create_llm_operator
    basic_llm_example()
    
    :ok
  end
  
  @doc """
  Set up the OpenAI API key.
  """
  def setup_api_key do
    IO.puts("Setting up OpenAI API key...")
    
    # Set directly in the configuration
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], System.get_env("OPENAI_API_KEY"))
    
    # Load config from environment variables
    EmberEx.Config.load_from_env()
    
    IO.puts("Configuration complete.\n")
  end

  @doc """
  Helper function to create an LLM operator with proper Ecto schema.
  """
  def create_llm_operator(prompt_template, output_schema_module, model_name \\ "gpt-3.5-turbo", opts \\ %{}) do
    # Create a specification using BasicSpecification instead of EctoSpecification
    # This is a simplified version that doesn't rely on EctoSpecification
    
    input_schema = nil  # We'll use nil for simplicity
    
    # Create a simple specification directly
    spec = EmberEx.Specifications.BasicSpecification.new(
      prompt_template,
      input_schema,
      output_schema_module
    )
    
    # Create a model callable
    model = EmberEx.Models.create_model_callable(model_name)
    
    # Create the operator
    LLMOperator.new(spec, model, opts)
  end
  
  @doc """
  Example of a basic LLM operator.
  """
  def basic_llm_example do
    IO.puts("\n=== Basic LLM Operator Example ===")
    
    # Create a simple LLM operator using our helper function
    llm_op = create_llm_operator(
      "Generate a short poem about {topic}.",
      PoemSchema,
      "gpt-3.5-turbo",
      %{temperature: 0.8}
    )
    
    IO.puts("Calling LLM operator with input...")
    result = EmberEx.Operators.Operator.call(llm_op, %{topic: "artificial intelligence"})
    
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.puts(result.poem)
    IO.puts("------------------------------\n")
  end
end

# Run the example
if System.get_env("OPENAI_API_KEY") do
  EmberEx.Examples.FixedOpenAIIntegration.run()
else
  IO.puts("""
  This example requires an OpenAI API key.
  Please set the OPENAI_API_KEY environment variable and run the script again.
  
  Example usage:
    OPENAI_API_KEY=your-api-key elixir examples/fixed_openai_integration.exs
  """)
end
