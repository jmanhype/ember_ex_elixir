#!/usr/bin/env elixir
# Updated OpenAI Integration Example for EmberEx
#
# This example demonstrates the proper way to use the EmberEx framework with OpenAI.
# It leverages the BasicSpecification module, the updated Models API, and proper
# operator adapter pattern.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.UpdatedOpenAIIntegration do
  @moduledoc """
  Updated example for OpenAI integration with EmberEx.
  
  This example shows how to:
  - Use the BasicSpecification module for simple JSON schemas
  - Use the updated Models API for OpenAI integration
  - Define proper adapter functions for LLMOperator
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator}
  alias EmberEx.Specifications.{BasicSpecification, EctoSpecification}
  
  # Define a simple Ecto schema for structured output
  defmodule PoemSchema do
    @moduledoc """
    Schema for poem generation output.
    """
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
  
  # Define a more complex schema for analysis output
  defmodule AnalysisSchema do
    @moduledoc """
    Schema for text analysis output.
    """
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :summary, :string
      field :sentiment, :string
      field :key_points, {:array, :string}
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:summary, :sentiment, :key_points])
      |> validate_required([:summary, :sentiment])
      |> validate_inclusion(:sentiment, ["positive", "negative", "neutral", "mixed"])
    end
  end
  
  @doc """
  Run all the examples.
  """
  def run do
    IO.puts("=== EmberEx Updated OpenAI Integration Example ===\n")
    
    # Set up OpenAI
    setup_api_key()
    
    # Run examples
    basic_llm_example()
    json_schema_example()
    ecto_schema_example()
    
    :ok
  end
  
  @doc """
  Set up the OpenAI API key.
  """
  def setup_api_key do
    IO.puts("Setting up OpenAI API key...")
    
    # Get the API key from environment
    api_key = System.get_env("OPENAI_API_KEY")
    if !api_key do
      IO.puts("Error: OPENAI_API_KEY environment variable not set.")
      System.halt(1)
    end
    
    # Configure EmberEx with the API key
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], api_key)
    EmberEx.Config.load_from_env()
    
    IO.puts("Configuration complete.\n")
  end
  
  @doc """
  Create an adapter function that works with LLMOperator.
  
  This bridges the gap between the EmberEx.Models API and the
  requirements of the LLMOperator.
  """
  def create_model_adapter(model_name, opts \\ []) do
    # Create a model callable from EmberEx.Models
    base_model = EmberEx.Models.model(model_name, opts)
    
    # Create the adapter function
    fn model_args ->
      try do
        # Extract the prompt from the model arguments
        prompt = case model_args do
          %{messages: [%{content: content} | _]} -> content
          %{messages: messages} when is_list(messages) ->
            # Find the first user message
            user_message = Enum.find(messages, fn msg -> 
              is_map(msg) && Map.get(msg, :role) == "user" 
            end)
            Map.get(user_message || %{}, :content, "")
          _ -> inspect(model_args)
        end
        
        # Call the base model
        response = base_model.(prompt)
        
        # Return in the format expected by LLMOperator
        {:ok, %{result: response.content}}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
  end
  
  @doc """
  Create an LLMOperator with the given specification.
  
  This function accepts either a BasicSpecification or an EctoSpecification.
  """
  def create_llm_operator(prompt_template, input_schema \\ nil, output_schema \\ nil, model_name \\ "gpt-3.5-turbo") do
    # Create a specification based on the type of schemas provided
    spec = cond do
      # If output schema is an Ecto schema module
      is_atom(output_schema) && Code.ensure_loaded?(output_schema) && 
          function_exported?(output_schema, :__schema__, 1) ->
        EctoSpecification.new(prompt_template, input_schema, output_schema)
        
      # Otherwise use BasicSpecification with JSON schema
      true ->
        json_output_schema = if output_schema do
          output_schema  # Already a JSON schema map
        else
          # Default schema for a result
          %{
            "type" => "object",
            "properties" => %{
              "result" => %{"type" => "string"}
            },
            "required" => ["result"]
          }
        end
        
        BasicSpecification.new(prompt_template, input_schema, json_output_schema)
    end
    
    # Create the adapter
    adapter = create_model_adapter(model_name, [temperature: 0.7])
    
    # Create and return the operator
    LLMOperator.new(spec, adapter)
  end
  
  @doc """
  Example using a basic LLM operator with simple text output.
  """
  def basic_llm_example do
    IO.puts("\n=== Basic LLM Operator Example ===")
    
    # Create an LLM operator with a simple prompt template
    llm_op = create_llm_operator(
      "Generate a short poem about {topic}.",
      nil,  # No input schema
      nil   # No output schema, just text
    )
    
    # Call the operator
    IO.puts("Generating poem about programming...")
    result = EmberEx.Operators.Operator.call(llm_op, %{topic: "programming"})
    
    # Display the result
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.puts(result.result)
    IO.puts("------------------------------\n")
  end
  
  @doc """
  Example using a JSON schema for structured output.
  """
  def json_schema_example do
    IO.puts("\n=== JSON Schema Example ===")
    
    # Define a JSON schema for the output
    output_schema = %{
      "type" => "object",
      "properties" => %{
        "analysis" => %{
          "type" => "object",
          "properties" => %{
            "summary" => %{"type" => "string"},
            "mood" => %{"type" => "string"},
            "themes" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          "required" => ["summary", "mood", "themes"]
        }
      },
      "required" => ["analysis"]
    }
    
    # Create an LLM operator with JSON schema
    llm_op = create_llm_operator(
      """
      Analyze the following text and provide:
      1. A brief summary
      2. The overall mood
      3. Key themes (as a list)
      
      Text: {text}
      """,
      nil,  # No input schema
      output_schema
    )
    
    # Sample text to analyze
    sample_text = "The EmberEx framework provides a functional approach to AI application development. It emphasizes composition, reusability, and performance optimization through its JIT system."
    
    # Call the operator
    IO.puts("Analyzing text...")
    result = EmberEx.Operators.Operator.call(llm_op, %{text: sample_text})
    
    # Display the result
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.inspect(result.result, label: "Raw result")
    IO.puts("------------------------------\n")
  end
  
  @doc """
  Example using an Ecto schema for structured output.
  """
  def ecto_schema_example do
    IO.puts("\n=== Ecto Schema Example ===")
    
    # Create a pipeline of operators for text analysis
    
    # 1. Preprocessing operator
    preprocessor = MapOperator.new(fn input ->
      # Simple preprocessing - convert text to lowercase
      Map.update(input, :text, "", &String.downcase/1)
    end)
    
    # 2. LLM operator with Ecto schema
    llm_op = create_llm_operator(
      """
      Analyze the following text and provide:
      1. A concise summary (1-2 sentences)
      2. The sentiment (must be one of: positive, negative, neutral, mixed)
      3. Key points (as a bullet list)
      
      Text: {text}
      """,
      nil,  # No input schema
      AnalysisSchema  # Using our Ecto schema for structured output
    )
    
    # 3. Postprocessing operator
    postprocessor = MapOperator.new(fn result ->
      # Add metadata and additional processing
      Map.merge(result, %{
        word_count: length(String.split(result.summary)),
        timestamp: DateTime.utc_now()
      })
    end)
    
    # Compose the operators into a sequence
    pipeline = SequenceOperator.new([
      preprocessor,
      llm_op,
      postprocessor
    ])
    
    # Sample text to analyze
    sample_text = "EmberEx is an exciting framework that makes building AI applications with language models simple and efficient. The functional approach provides great composability and the JIT system improves performance."
    
    # Call the pipeline
    IO.puts("Analyzing text with structured output...")
    result = EmberEx.Operators.Operator.call(pipeline, %{text: sample_text})
    
    # Display the result
    IO.puts("\nStructured Analysis Result:")
    IO.puts("------------------------------")
    IO.puts("Summary: #{result.summary}")
    IO.puts("Sentiment: #{result.sentiment}")
    IO.puts("\nKey Points:")
    if result.key_points, do: Enum.each(result.key_points, &IO.puts("- #{&1}"))
    IO.puts("\nMeta: Word count: #{result.word_count}, Timestamp: #{result.timestamp}")
    IO.puts("------------------------------\n")
  end
end

# Run the examples
EmberEx.Examples.UpdatedOpenAIIntegration.run()
