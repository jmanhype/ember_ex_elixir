#!/usr/bin/env elixir
# Complete OpenAI Pipeline Example for EmberEx
#
# This example demonstrates a fully-functional integration with OpenAI using:
# 1. Proper Ecto schemas for structured inputs and outputs
# 2. A full adapter between EmberEx.Models and the LLMOperator system
# 3. Composition of operators for pre/post-processing 

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.CompleteOpenAIPipeline do
  @moduledoc """
  A comprehensive example of EmberEx with OpenAI integration using the operator system.
  
  This demonstrates:
  - Proper Ecto schema definitions for structured data
  - A complete model adapter for bridging EmberEx.Models and LLMOperator
  - Operator composition for building pipelines
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator}
  
  #############################################################
  # Schema Definitions
  #############################################################
  
  # Basic poem input schema
  defmodule PoemInput do
    @moduledoc """
    Input schema for generating poems with specific topics and styles.
    """
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :topic, :string
      field :style, :string, default: "free verse"
      field :lines, :integer, default: 4
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:topic, :style, :lines])
      |> validate_required([:topic])
      |> validate_inclusion(:style, ["free verse", "haiku", "sonnet", "limerick"])
      |> validate_number(:lines, greater_than: 0, less_than: 20)
    end
  end
  
  # Basic poem output schema
  defmodule PoemOutput do
    @moduledoc """
    Output schema for poem generation results.
    """
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :poem, :string
      field :title, :string
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:poem, :title])
      |> validate_required([:poem])
    end
  end
  
  # Complex story planning input schema
  defmodule StoryPlanInput do
    @moduledoc """
    Input schema for planning a story.
    """
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :genre, :string
      field :theme, :string
      field :setting, :string
      field :characters, :integer, default: 2
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:genre, :theme, :setting, :characters])
      |> validate_required([:genre, :theme])
      |> validate_number(:characters, greater_than: 0, less_than: 10)
    end
  end
  
  # Complex story planning output schema
  defmodule StoryPlanOutput do
    @moduledoc """
    Output schema for story planning results.
    """
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :title, :string
      field :plot_summary, :string
      field :character_descriptions, {:array, :map}, default: []
      field :key_scenes, {:array, :string}, default: []
      field :estimated_word_count, :integer
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:title, :plot_summary, :character_descriptions, :key_scenes, :estimated_word_count])
      |> validate_required([:title, :plot_summary])
      |> validate_length(:character_descriptions, min: 1)
      |> validate_length(:key_scenes, min: 1)
    end
  end
  
  #############################################################
  # Adapter for EmberEx.Models to LLMOperator
  #############################################################
  
  @doc """
  Create a complete adapter between EmberEx.Models and LLMOperator.
  
  This adapter properly handles:
  1. Converting input from the LLMOperator format to what EmberEx.Models expects
  2. Converting output from EmberEx.Models to what LLMOperator expects
  3. Proper error handling and schema validation
  
  ## Parameters
  
  - model_name: The name of the model to use (e.g., "gpt-4o")
  - opts: Additional options to pass to the model (e.g., temperature)
  
  ## Returns
  
  A callable function that can be used with LLMOperator
  """
  def create_model_adapter(model_name, opts \\ []) do
    # Create the base model callable
    base_model = EmberEx.Models.model(model_name, opts)
    
    # Create an adapter function that handles format conversion
    fn model_args ->
      try do
        # Extract prompt from the messages
        prompt = extract_prompt_from_args(model_args)
        
        # Get response schema
        output_schema = Map.get(model_args, :response_model)
        
        # Call the base model with the extracted prompt
        response = base_model.(prompt)
        
        # Process the response according to schema
        case process_response(response.content, output_schema) do
          {:ok, processed_response} ->
            {:ok, processed_response}
            
          {:error, reason} ->
            {:error, "Failed to process response: #{inspect(reason)}"}
        end
      rescue
        e ->
          # Handle any errors
          {:error, "Error in model adapter: #{Exception.message(e)}"}
      end
    end
  end
  
  @doc """
  Extract a usable prompt from the model arguments.
  
  ## Parameters
  
  - model_args: The arguments passed to the model function
  
  ## Returns
  
  A string prompt that can be used with EmberEx.Models
  """
  def extract_prompt_from_args(model_args) do
    case model_args do
      %{messages: messages} when is_list(messages) ->
        # Extract content from user messages
        messages
        |> Enum.filter(fn msg -> 
          is_map(msg) && Map.get(msg, :role) == "user" 
        end)
        |> Enum.map(fn msg -> Map.get(msg, :content, "") end)
        |> Enum.join("\n\n")
        
      string when is_binary(string) ->
        # If it's already a string, use it directly
        string
        
      _ ->
        # Try to extract a prompt from other formats or use empty string
        inspect(model_args)
    end
  end
  
  @doc """
  Process the raw response from the model according to the expected schema.
  
  ## Parameters
  
  - content: The raw content string from the model
  - schema: The schema module or map that defines the expected structure
  
  ## Returns
  
  {:ok, processed_data} or {:error, reason}
  """
  def process_response(content, schema) when is_atom(schema) and is_binary(content) do
    # For Ecto schema modules, we need structured data
    try do
      # For PoemOutput, parse simply
      case schema do
        PoemOutput ->
          # Try to extract title from the content if present
          {title, poem} = case Regex.run(~r/^(.*)\n(.*)$/s, String.trim(content)) do
            [_, possible_title, rest] ->
              if String.length(possible_title) < 100, do: {possible_title, rest}, else: {"Untitled", content}
            _ ->
              {"Untitled", content}
          end
          
          {:ok, %{title: title, poem: poem}}
          
        StoryPlanOutput ->
          # More complex parsing for story plan
          parse_story_plan(content)
          
        _ ->
          # Default case - just put the content in the first field of the schema
          fields = schema.__schema__(:fields)
          if length(fields) > 0 do
            {:ok, Map.put(%{}, List.first(fields), content)}
          else
            {:error, "Schema has no fields"}
          end
      end
    rescue
      e -> 
        {:error, "Failed to parse response for schema #{inspect(schema)}: #{Exception.message(e)}"}
    end
  end
  
  def process_response(content, %{"type" => "object"} = schema) when is_binary(content) do
    # For JSON schema, try to extract required fields
    required = Map.get(schema, "required", [])
    
    if length(required) > 0 do
      # Use the first required field
      field = List.first(required)
      {:ok, %{String.to_atom(field) => content}}
    else
      # No required fields, use "result"
      {:ok, %{result: content}}
    end
  end
  
  def process_response(content, _schema) do
    # Default case - just return the content as is
    {:ok, %{result: content}}
  end
  
  @doc """
  Parse story plan output from raw text into structured data.
  This is a simplified version - in a real app, you might use a more sophisticated parser.
  """
  def parse_story_plan(content) do
    # Extract title (first line)
    title = content |> String.split("\n", parts: 2) |> List.first() |> String.trim()
    
    # Extract plot summary (looks for a section labeled "Plot Summary" or similar)
    plot_summary = case Regex.run(~r/(?:Summary|Plot):(.*?)(?:Characters|Scenes|\Z)/si, content) do
      [_, summary] -> String.trim(summary)
      _ -> "No plot summary found"
    end
    
    # Extract character descriptions (simple version)
    characters = case Regex.run(~r/Characters?:(.*?)(?:Scenes|Key Scenes|\Z)/si, content) do
      [_, char_section] -> 
        char_section
        |> String.split(~r/\d+\.\s+|\n\s*-\s+|\n+/s)
        |> Enum.filter(fn s -> String.trim(s) != "" end)
        |> Enum.map(fn char -> %{description: String.trim(char)} end)
      _ -> [%{description: "Default character"}]
    end
    
    # Extract key scenes
    scenes = case Regex.run(~r/(?:Key )?Scenes?:(.*?)(?:Word Count|\Z)/si, content) do
      [_, scenes_section] ->
        scenes_section
        |> String.split(~r/\d+\.\s+|\n\s*-\s+|\n+/s)
        |> Enum.filter(fn s -> String.trim(s) != "" end)
        |> Enum.map(&String.trim/1)
      _ -> ["Scene 1"]
    end
    
    # Extract estimated word count
    word_count = case Regex.run(~r/(?:Word Count|Length):\s*(?:approximately\s*)?(\d+)/i, content) do
      [_, count] -> String.to_integer(count)
      _ -> 5000  # Default estimate
    end
    
    {:ok, %{
      title: title,
      plot_summary: plot_summary,
      character_descriptions: characters,
      key_scenes: scenes,
      estimated_word_count: word_count
    }}
  end
  
  #############################################################
  # Operator Pipeline Examples
  #############################################################
  
  @doc """
  Run all examples.
  """
  def run do
    IO.puts("=== EmberEx Complete OpenAI Pipeline Example ===\n")
    
    # Set up OpenAI
    setup_api_key()
    
    # Run basic poem example
    run_poem_example()
    
    # Run full pipeline example
    run_pipeline_example()
    
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
  Run a basic poem generation example using the LLMOperator.
  """
  def run_poem_example do
    IO.puts("\n=== Basic Poem Example ===")
    
    # Create specification with Ecto schemas
    spec = EmberEx.Specifications.EctoSpecification.new(
      """
      Write a {style} poem about {topic} with approximately {lines} lines.
      Make it creative and original.
      """,
      PoemInput,
      PoemOutput
    )
    
    # Create model adapter
    adapter = create_model_adapter("gpt-3.5-turbo", [temperature: 0.7])
    
    # Create LLMOperator
    llm_op = LLMOperator.new(spec, adapter)
    
    # Call the operator
    IO.puts("Generating poem...")
    result = EmberEx.Operators.Operator.call(llm_op, %{
      topic: "quantum computing",
      style: "sonnet",
      lines: 14
    })
    
    # Display the result
    IO.puts("\nTitle: #{result.title}")
    IO.puts("\nPoem:")
    IO.puts("------------------------------")
    IO.puts(result.poem)
    IO.puts("------------------------------\n")
  end
  
  @doc """
  Run a full pipeline example using multiple operators.
  """
  def run_pipeline_example do
    IO.puts("\n=== Full Pipeline Example ===")
    
    # Create story planning specification
    spec = EmberEx.Specifications.EctoSpecification.new(
      """
      Create a detailed story plan with the following parameters:
      - Genre: {genre}
      - Theme: {theme}
      - Setting: {setting}
      - Number of main characters: {characters}
      
      Include:
      1. A title
      2. Plot summary
      3. Character descriptions
      4. Key scenes
      5. Estimated word count
      """,
      StoryPlanInput,
      StoryPlanOutput
    )
    
    # Create model adapter with GPT-4 Turbo
    adapter = create_model_adapter("gpt-4o", [temperature: 0.8])
    
    # Create a preprocessing operator
    preprocessor = MapOperator.new(fn input ->
      # Add defaults if not provided
      input
      |> Map.put_new(:setting, "near future")
      |> Map.put_new(:characters, 3)
    end)
    
    # Create the LLM operator
    llm_op = LLMOperator.new(spec, adapter)
    
    # Create a postprocessing operator
    postprocessor = MapOperator.new(fn result ->
      # Add metadata and analytics
      word_count = result.estimated_word_count
      character_count = length(result.character_descriptions)
      
      # Return enhanced result
      Map.merge(result, %{
        metadata: %{
          created_at: DateTime.utc_now(),
          complexity_score: word_count / 1000 * (character_count / 2),
          estimated_reading_time: round(word_count / 250)  # Average reading speed
        }
      })
    end)
    
    # Compose the operators in sequence
    pipeline = SequenceOperator.new([
      preprocessor,
      llm_op,
      postprocessor
    ])
    
    # Call the pipeline
    IO.puts("Generating story plan...")
    result = EmberEx.Operators.Operator.call(pipeline, %{
      genre: "science fiction",
      theme: "artificial intelligence ethics"
    })
    
    # Display the result
    IO.puts("\nTitle: #{result.title}")
    IO.puts("\nPlot Summary:")
    IO.puts(result.plot_summary)
    
    IO.puts("\nCharacters:")
    Enum.each(result.character_descriptions, fn char ->
      IO.puts("- #{char.description}")
    end)
    
    IO.puts("\nKey Scenes:")
    Enum.each(result.key_scenes, fn scene ->
      IO.puts("- #{scene}")
    end)
    
    IO.puts("\nEstimated Word Count: #{result.estimated_word_count}")
    IO.puts("Estimated Reading Time: #{result.metadata.estimated_reading_time} minutes")
    IO.puts("Complexity Score: #{result.metadata.complexity_score}")
    IO.puts("------------------------------\n")
  end
end

# Run the examples
EmberEx.Examples.CompleteOpenAIPipeline.run()
