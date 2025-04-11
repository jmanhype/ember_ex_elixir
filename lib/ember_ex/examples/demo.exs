#!/usr/bin/env elixir

# Add the current directory to the code path
Code.append_path("_build/dev/lib/ember_ex/ebin")
Code.append_path("_build/dev/lib/instructor/ebin")
Code.append_path("_build/dev/lib/jason/ebin")
Code.append_path("_build/dev/lib/ecto/ebin")
Code.append_path("_build/dev/lib/finch/ebin")

defmodule EmberEx.Examples.Demo do
  @moduledoc """
  A demonstration script for the EmberEx library.
  
  This script shows how to use EmberEx to create a simple AI workflow
  that processes text in multiple ways.
  """
  
  alias EmberEx.Operators.{MapOperator, SequenceOperator, BranchOperator, LLMOperator}
  alias EmberEx.Specifications.EctoSpecification
  alias EmberEx.XCS.Graph
  
  @doc """
  Run the demonstration.
  """
  @spec run() :: :ok
  def run do
    IO.puts("EmberEx Demonstration")
    IO.puts("====================")
    
    # Set up a mock API key for demonstration purposes
    # In a real application, this would be set in your environment
    System.put_env("OPENAI_API_KEY", "sk-demo-key")
    
    # Create a simple workflow
    IO.puts("\nCreating workflow...")
    workflow = create_workflow()
    
    # Sample inputs
    inputs = [
      %{
        text: "Artificial intelligence (AI) is intelligence demonstrated by machines, as opposed to intelligence displayed by animals and humans. Example tasks in which this is done include speech recognition, computer vision, translation between (natural) languages, as well as other mappings of inputs.",
        action: "summarize"
      },
      %{
        text: "Machine learning (ML) is a field of inquiry devoted to understanding and building methods that 'learn', that is, methods that leverage data to improve performance on some set of tasks.",
        action: "analyze"
      },
      %{
        text: "Hello world, this is a test.",
        action: "translate",
        language: "Spanish"
      }
    ]
    
    # Process each input
    Enum.each(inputs, fn input ->
      IO.puts("\nProcessing input: #{inspect(input)}")
      
      # Execute the workflow
      # In a real application, this would make actual API calls
      # For this demo, we'll simulate the responses
      result = simulate_execution(workflow, input)
      
      IO.puts("Result: #{inspect(result)}")
    end)
    
    IO.puts("\nDemonstration complete!")
    :ok
  end
  
  @doc """
  Create a workflow that processes text in different ways based on the action.
  """
  @spec create_workflow() :: Graph.t()
  def create_workflow do
    # Create operators for different text processing tasks
    summarize_op = create_summarize_operator()
    analyze_op = create_analyze_operator()
    translate_op = create_translate_operator()
    
    # Create a router operator that selects the appropriate operator based on the action
    router_op = create_router_operator()
    
    # Create a graph
    graph = Graph.new(%{name: "Text Processing Workflow"})
    
    # Add nodes
    |> Graph.add_node("input", router_op, %{description: "Input router"})
    |> Graph.add_node("summarize", summarize_op, %{description: "Text summarization"})
    |> Graph.add_node("analyze", analyze_op, %{description: "Text analysis"})
    |> Graph.add_node("translate", translate_op, %{description: "Text translation"})
    |> Graph.add_node("output", create_output_operator(), %{description: "Output formatter"})
    
    # Add edges
    |> Graph.add_edge("input", "summarize", "summarize_input", "input")
    |> Graph.add_edge("input", "analyze", "analyze_input", "input")
    |> Graph.add_edge("input", "translate", "translate_input", "input")
    |> Graph.add_edge("summarize", "output", nil, "result")
    |> Graph.add_edge("analyze", "output", nil, "result")
    |> Graph.add_edge("translate", "output", nil, "result")
  end
  
  # Create a router operator that directs input to the appropriate operator
  defp create_router_operator do
    MapOperator.new(fn input ->
      case input.action do
        "summarize" ->
          %{
            summarize_input: %{text: input.text},
            analyze_input: nil,
            translate_input: nil
          }
          
        "analyze" ->
          %{
            summarize_input: nil,
            analyze_input: %{text: input.text},
            translate_input: nil
          }
          
        "translate" ->
          %{
            summarize_input: nil,
            analyze_input: nil,
            translate_input: %{
              text: input.text,
              target_language: input.language
            }
          }
          
        _ ->
          raise "Unknown action: #{input.action}"
      end
    end)
  end
  
  # Create a summarization operator
  defp create_summarize_operator do
    # In a real application, this would use the actual LLMOperator
    # For this demo, we'll create a simple MapOperator that simulates the behavior
    MapOperator.new(fn input ->
      %{summary: "Summary of: #{String.slice(input.text, 0, 50)}..."}
    end)
  end
  
  # Create an analysis operator
  defp create_analyze_operator do
    # In a real application, this would use the actual LLMOperator
    # For this demo, we'll create a simple MapOperator that simulates the behavior
    MapOperator.new(fn input ->
      %{
        topics: ["AI", "Machine Learning", "Technology"],
        sentiment: "positive",
        complexity: "medium"
      }
    end)
  end
  
  # Create a translation operator
  defp create_translate_operator do
    # In a real application, this would use the actual LLMOperator
    # For this demo, we'll create a simple MapOperator that simulates the behavior
    MapOperator.new(fn input ->
      case input.target_language do
        "Spanish" ->
          %{translated_text: "Hola mundo, esto es una prueba."}
        "French" ->
          %{translated_text: "Bonjour le monde, c'est un test."}
        _ ->
          %{translated_text: "Translation not available for #{input.target_language}"}
      end
    end)
  end
  
  # Create an output operator
  defp create_output_operator do
    MapOperator.new(fn input ->
      # Only one of these will be non-nil
      result = input.result
      
      # Add metadata to the result
      Map.merge(result, %{
        processed_at: DateTime.utc_now() |> DateTime.to_string(),
        version: "1.0.0"
      })
    end)
  end
  
  # Simulate execution of the workflow
  defp simulate_execution(graph, input) do
    # In a real application, this would use the actual Graph.execute function
    # For this demo, we'll simulate the execution
    case input.action do
      "summarize" ->
        %{
          summary: "Summary of: #{String.slice(input.text, 0, 50)}...",
          processed_at: DateTime.utc_now() |> DateTime.to_string(),
          version: "1.0.0"
        }
        
      "analyze" ->
        %{
          topics: ["AI", "Machine Learning", "Technology"],
          sentiment: "positive",
          complexity: "medium",
          processed_at: DateTime.utc_now() |> DateTime.to_string(),
          version: "1.0.0"
        }
        
      "translate" ->
        %{
          translated_text: "Hola mundo, esto es una prueba.",
          processed_at: DateTime.utc_now() |> DateTime.to_string(),
          version: "1.0.0"
        }
        
      _ ->
        raise "Unknown action: #{input.action}"
    end
  end
end

# Run the demonstration
EmberEx.Examples.Demo.run()
