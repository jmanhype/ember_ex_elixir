# Simple test script for EmberEx with a real OpenAI model
# This script creates a custom MapOperator that directly interacts with the OpenAI API

# Set the OpenAI API key
System.put_env("OPENAI_API_KEY", "YOUR_OPENAI_API_KEY_HERE")

IO.puts("\n🚀 Testing EmberEx with real OpenAI models")
IO.puts("=========================================")

# Test direct model usage
IO.puts("\n🧪 Test 1: Direct Model Usage")
model = EmberEx.Models.model("gpt-4o")
IO.puts("Calling model with a simple prompt...")
response = model.("What is the capital of France?")

IO.puts("\n📝 Model Response:")
IO.puts(response.content)

# Test MapOperator with model
IO.puts("\n🧪 Test 2: MapOperator with Model")
map_op = EmberEx.Operators.MapOperator.new_with_name(
  "test_map_op",
  nil,
  fn _input ->
    model = EmberEx.Models.model("gpt-4o")
    response = model.("Generate a short poem about programming")
    %{poem: response.content}
  end
)

IO.puts("Running MapOperator...")
map_result = EmberEx.Operators.Operator.call(map_op, %{})

IO.puts("\n📝 MapOperator Result:")
IO.puts(map_result.poem)

# Test with custom formatting
IO.puts("\n🧪 Test 3: Custom Formatting")
format_op = EmberEx.Operators.MapOperator.new_with_name(
  "format_op",
  nil,
  fn input ->
    model = EmberEx.Models.model("gpt-4o")
    prompt = "Summarize this text in #{input.max_words} words or less: #{input.text}"
    response = model.(prompt)
    %{summary: response.content}
  end
)

IO.puts("Running format operator with custom input...")
format_input = %{
  text: "The Ember framework is a powerful tool for building AI applications using Language Models (LLMs). It provides a structured approach to building LLM applications with features like operators, graphs, and execution engines. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging the functional programming paradigm and concurrency features of the BEAM.",
  max_words: 30
}

format_result = EmberEx.Operators.Operator.call(format_op, format_input)

IO.puts("\n📝 Format Result:")
IO.puts(format_result.summary)

IO.puts("\n✅ All tests completed!")
