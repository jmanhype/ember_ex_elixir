# Simple test script for EmberEx with a real OpenAI model
# Tests basic functionality with the OpenAI API

# Set the OpenAI API key (use a valid key for testing)
System.put_env("OPENAI_API_KEY", "your_openai_api_key")

# Start the application to ensure all dependencies are loaded
Application.ensure_all_started(:ember_ex)

IO.puts("\n🚀 Testing EmberEx with real OpenAI models")
IO.puts("=========================================")

# Define the model name - use "gpt-3.5-turbo" for a standard model
MODEL_NAME = "gpt-3.5-turbo"

# Test 1: Direct model usage with simple prompt
try do
  IO.puts("\n🧪 Test 1: Direct Model Usage")
  model_fn = EmberEx.Models.model(MODEL_NAME)
  IO.puts("Calling model with a simple prompt...")
  response = model_fn.("What is the capital of France?")
  
  IO.puts("\n📝 Model Response:")
  IO.puts(response.content)
  
  # Test 2: MapOperator with model
  IO.puts("\n🧪 Test 2: MapOperator with Model")
  map_op = EmberEx.Operators.MapOperator.new_with_name(
    "test_map_op",
    nil,
    fn _input ->
      model = EmberEx.Models.model(MODEL_NAME)
      response = model.("Generate a short poem about programming (2-4 lines only)")
      %{poem: response.content}
    end
  )
  
  IO.puts("Running MapOperator...")
  map_result = EmberEx.Operators.Operator.call(map_op, %{})
  
  IO.puts("\n📝 MapOperator Result:")
  IO.puts(map_result.poem)
  
  # Test 3: More complex example with LLMOperator and input formatting
  IO.puts("\n🧪 Test 3: Custom Formatting")
  format_op = EmberEx.Operators.MapOperator.new_with_name(
    "format_op",
    nil,
    fn input ->
      model = EmberEx.Models.model(MODEL_NAME)
      prompt = "Summarize this text in #{input.max_words} words or less: #{input.text}"
      response = model.(prompt)
      %{summary: response.content}
    end
  )
  
  IO.puts("Running format operator with custom input...")
  format_input = %{
    text: "The Ember framework is a tool for building AI applications using Language Models (LLMs). It provides a structured approach with features like operators, graphs, and execution engines. This port to Elixir brings these capabilities to the Elixir ecosystem while leveraging the functional programming paradigm.",
    max_words: 20
  }
  
  format_result = EmberEx.Operators.Operator.call(format_op, format_input)
  
  IO.puts("\n📝 Format Result:")
  IO.puts(format_result.summary)
  
  IO.puts("\n✅ All tests completed successfully!")
rescue
  error ->
    IO.puts("\n❌ Error during testing:")
    IO.puts(Exception.message(error))
    IO.puts("\nStack trace:")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))
end
