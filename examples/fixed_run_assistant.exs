#!/usr/bin/env elixir
# Fixed Run Assistant Example for EmberEx
#
# This example demonstrates how to create and run an LLM-powered assistant
# using the updated EmberEx framework components.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.FixedAssistant do
  @moduledoc """
  A fixed implementation of the assistant example using the updated EmberEx framework.
  
  This example demonstrates how to:
  1. Create an assistant with a specific persona
  2. Enable the assistant to use tools (operators)
  3. Run a conversation with the assistant
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator}
  alias EmberEx.Specifications.BasicSpecification
  
  @doc """
  Run the assistant example.
  """
  def run do
    IO.puts("=== EmberEx Fixed Assistant Example ===\n")
    
    # Set up OpenAI
    setup_api_key()
    
    # Create an assistant
    assistant = create_assistant()
    
    # Run a conversation
    run_conversation(assistant)
    
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
  Create a model adapter compatible with LLMOperator.
  """
  def create_model_adapter(model_name, opts \\ []) do
    # Create the base model callable
    base_model = EmberEx.Models.model(model_name, opts)
    
    # Return an adapter function
    fn model_args ->
      try do
        # Extract the prompt from the model arguments
        prompt = case model_args do
          %{messages: messages} when is_list(messages) ->
            # Format messages as a conversation
            messages
            |> Enum.map(fn msg -> 
              role = Map.get(msg, :role, "user")
              content = Map.get(msg, :content, "")
              "#{String.upcase(role)}: #{content}"
            end)
            |> Enum.join("\n\n")
            
          _ -> inspect(model_args)
        end
        
        # Call the base model
        response = base_model.(prompt)
        
        # Return in the format expected by LLMOperator
        {:ok, %{response: response.content}}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
  end
  
  @doc """
  Create an assistant with a specific persona and tools.
  """
  def create_assistant do
    # Define the assistant's persona and instructions
    system_prompt = """
    You are EmberEx Assistant, an AI helper specialized in software development.
    
    You have access to the following tools:
    1. Calculator - For performing mathematical calculations
    2. TextAnalyzer - For analyzing text and extracting information
    
    When a user asks a question, think step by step about how to solve it.
    If it involves calculations or text analysis, use the appropriate tool.
    """
    
    # Create a specification for the assistant
    spec = BasicSpecification.new(
      # Prompt template includes conversation history and system prompt
      """
      SYSTEM: #{system_prompt}
      
      {conversation_history}
      
      USER: {user_input}
      
      ASSISTANT:
      """,
      nil,  # No input schema
      %{
        "type" => "object",
        "properties" => %{
          "response" => %{"type" => "string"}
        },
        "required" => ["response"]
      }
    )
    
    # Create a model adapter
    adapter = create_model_adapter("gpt-3.5-turbo", [temperature: 0.7])
    
    # Create the assistant operator
    assistant_op = LLMOperator.new(spec, adapter)
    
    # Create tool operators
    calculator_op = create_calculator_operator()
    text_analyzer_op = create_text_analyzer_operator()
    
    # Return the assistant with its tools
    %{
      operator: assistant_op,
      tools: %{
        "calculator" => calculator_op,
        "text_analyzer" => text_analyzer_op
      },
      conversation: []  # Empty conversation history
    }
  end
  
  @doc """
  Create a calculator operator.
  """
  def create_calculator_operator do
    MapOperator.new(fn input ->
      # Extract expression from input
      expression = Map.get(input, :expression, "0")
      
      # Safely evaluate the expression
      result = try do
        {result, _} = Code.eval_string(expression)
        "#{inspect(result)}"
      rescue
        e -> "Error: #{Exception.message(e)}"
      end
      
      # Return the result
      %{result: result}
    end)
  end
  
  @doc """
  Create a text analyzer operator.
  """
  def create_text_analyzer_operator do
    MapOperator.new(fn input ->
      # Extract text from input
      text = Map.get(input, :text, "")
      
      # Perform analysis
      words = String.split(text, ~r/\s+/)
      word_count = length(words)
      
      # Count character frequencies
      char_freq = text
        |> String.downcase()
        |> String.graphemes()
        |> Enum.filter(fn c -> String.match?(c, ~r/[a-z]/) end)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.take(5)
        |> Enum.map(fn {char, count} -> "#{char}: #{count}" end)
        |> Enum.join(", ")
      
      # Return analysis result
      %{
        result: %{
          word_count: word_count,
          character_count: String.length(text),
          top_characters: char_freq
        }
      }
    end)
  end
  
  @doc """
  Run a conversation with the assistant.
  """
  def run_conversation(assistant) do
    # Sample conversation
    conversation = [
      {"Hello! Can you help me solve a math problem?", nil},
      {"Sure! What's the math problem you need help with?", nil},
      {"What is 345 * 892?", "calculator"},
      {"What can you tell me about this text: 'EmberEx is a functional programming framework for AI applications'?", "text_analyzer"}
    ]
    
    # Track conversation history
    history = []
    
    # Process each turn in the conversation
    Enum.reduce(conversation, history, fn {input, tool}, acc ->
      # Display user input
      IO.puts("\nUSER: #{input}")
      
      # Format conversation history
      history_text = format_conversation_history(acc)
      
      # Get assistant response
      response = case tool do
        nil ->
          # Direct response without tool use
          EmberEx.Operators.Operator.call(
            assistant.operator, 
            %{user_input: input, conversation_history: history_text}
          )
          
        tool_name ->
          # First get assistant's thoughts
          thinking = EmberEx.Operators.Operator.call(
            assistant.operator, 
            %{
              user_input: "#{input}\n\nBefore responding, think about how to use the #{tool_name} tool.", 
              conversation_history: history_text
            }
          )
          
          # Extract tool parameters from thinking
          params = extract_tool_params(thinking.response, tool_name)
          
          # Call the tool
          tool_op = Map.get(assistant.tools, tool_name)
          tool_result = EmberEx.Operators.Operator.call(tool_op, params)
          
          # Get final response with tool results
          EmberEx.Operators.Operator.call(
            assistant.operator, 
            %{
              user_input: "#{input}\n\nTool #{tool_name} returned: #{inspect(tool_result)}", 
              conversation_history: history_text
            }
          )
      end
      
      # Display assistant response
      IO.puts("\nASSISTANT: #{response.response}")
      
      # Update conversation history
      acc ++ [
        %{role: "user", content: input},
        %{role: "assistant", content: response.response}
      ]
    end)
  end
  
  @doc """
  Format the conversation history for the prompt.
  """
  def format_conversation_history(history) do
    history
    |> Enum.map(fn %{role: role, content: content} ->
      "#{String.upcase(role)}: #{content}"
    end)
    |> Enum.join("\n\n")
  end
  
  @doc """
  Extract tool parameters from the assistant's response.
  This is a simplified version that would need to be improved
  for production use with proper parsing.
  """
  def extract_tool_params(response, "calculator") do
    # Extract expression between backticks, parentheses, or just digits and operators
    case Regex.run(~r/`([^`]+)`|calculate\s*\(([^)]+)\)|([\d\s+\-*\/\(\)\.]+)/, response) do
      [_, expression, nil, nil] -> %{expression: expression}
      [_, nil, expression, nil] -> %{expression: expression}
      [_, nil, nil, expression] -> %{expression: expression}
      _ -> %{expression: "0"}  # Default
    end
  end
  
  def extract_tool_params(response, "text_analyzer") do
    # Extract text between quotes or after specific phrases
    case Regex.run(~r/"([^"]+)"|analyze text[:]\s*(.+)|text[:]\s*(.+)/i, response) do
      [_, text, nil, nil] -> %{text: text}
      [_, nil, text, nil] -> %{text: text}
      [_, nil, nil, text] -> %{text: text}
      _ -> %{text: ""}  # Default
    end
  end
  
  def extract_tool_params(_response, _tool) do
    %{}  # Default empty params
  end
end

# Run the example
EmberEx.Examples.FixedAssistant.run()
