#!/usr/bin/env elixir
# Direct OpenAI API integration example with EmberEx
#
# This example bypasses the operator system and uses EmberEx.Models directly
# to interact with OpenAI's API.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.DirectOpenAIExample do
  @moduledoc """
  A direct example of using OpenAI with EmberEx.Models.
  """
  
  @doc """
  Run the example
  """
  def run do
    IO.puts("=== EmberEx Direct OpenAI API Example ===\n")
    
    # Configure the OpenAI API key
    api_key = System.get_env("OPENAI_API_KEY")
    if !api_key do
      IO.puts("Error: OPENAI_API_KEY environment variable not set.")
      System.halt(1)
    end
    
    # Set up the API key
    IO.puts("Setting up OpenAI API key...")
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], api_key)
    EmberEx.Config.load_from_env()
    IO.puts("Configuration complete.\n")
    
    # Create a model using the EmberEx.Models.model function
    IO.puts("Creating model callable...")
    model_fn = EmberEx.Models.model("gpt-3.5-turbo", [temperature: 0.7]) 
    
    # Create a prompt
    prompt = "Generate a short poem about functional programming."
    IO.puts("Calling OpenAI model with prompt: #{prompt}\n")
    
    # Call the model function
    response = model_fn.(prompt)
    
    # Display the result
    IO.puts("Result:")
    IO.puts("------------------------------")
    IO.puts(response.content)
    IO.puts("------------------------------\n")
    
    # Show metadata
    IO.puts("Metadata:")
    IO.puts("Model: #{response.metadata.model_id}")
    IO.puts("Provider: #{response.metadata.provider}")
    IO.puts("Timestamp: #{response.metadata.timestamp}")
  end
end

# Run the example
EmberEx.Examples.DirectOpenAIExample.run()
