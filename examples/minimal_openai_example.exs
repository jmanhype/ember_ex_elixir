#!/usr/bin/env elixir
# Minimal OpenAI integration example with EmberEx
#
# This example uses the lowest-level API to call OpenAI directly,
# bypassing the operator system to isolate the issue.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.MinimalOpenAIExample do
  @moduledoc """
  A bare-bones example of using OpenAI with EmberEx, focusing on
  direct model interaction.
  """
  
  @doc """
  Run the example
  """
  def run do
    IO.puts("=== EmberEx Minimal OpenAI Integration Example ===\n")
    
    # Configure the OpenAI API key
    api_key = System.get_env("OPENAI_API_KEY")
    if !api_key do
      IO.puts("Error: OPENAI_API_KEY environment variable not set.")
      System.halt(1)
    end
    
    IO.puts("Setting up OpenAI API key...")
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], api_key)
    EmberEx.Config.load_from_env()
    IO.puts("Configuration complete.\n")
    
    # Initialize the EmberEx system (required for proper operation)
    Application.ensure_all_started(:ember_ex)
    
    IO.puts("Calling OpenAI model directly...\n")
    
    # Create a simple message for the API
    message = "Generate a short poem about functional programming."
    
    # Make the call directly without any operators
    case direct_openai_call(message) do
      {:ok, result} ->
        IO.puts("Result:")
        IO.puts("------------------------------")
        IO.puts(result)
        IO.puts("------------------------------")
      
      {:error, error} ->
        IO.puts("Error calling OpenAI API:")
        IO.puts(inspect(error))
    end
  end
  
  @doc """
  Make a direct call to OpenAI API using EmberEx.Models module
  """
  def direct_openai_call(prompt) do
    try do
      # Create the model configuration
      model_config = %{
        messages: [
          %{role: "user", content: prompt}
        ],
        model: "gpt-3.5-turbo",
        temperature: 0.7
      }
      
      # Call OpenAI directly through the provider
      EmberEx.Models.Providers.OpenAI.call(model_config)
    rescue
      e -> {:error, "API call failed: #{Exception.message(e)}"}
    end
  end
end

# Run the example
EmberEx.Examples.MinimalOpenAIExample.run()
