# Test script for EmberEx with a real OpenAI model
# This script applies a temporary patch to make the SchemaGenerator work

# Set the OpenAI API key
System.put_env("OPENAI_API_KEY", "YOUR_OPENAI_API_KEY_HERE")

# Start the application
Application.ensure_all_started(:ember_ex)

# Load our patch module
Code.require_file("fix_schema_generator.ex")

# Apply the patch
EmberEx.Specifications.SchemaGeneratorFix.patch_schema_generator()

IO.puts("\n🚀 Testing EmberEx with real OpenAI models")
IO.puts("=========================================")

# Create a custom, simplified LLM operator for testing
create_test_operator = fn prompt_template, model_name ->
  # Create a model callable that manually formats the JSON response
  model_fn = fn prompt ->
    response = EmberEx.Models.model(model_name).("Respond with a valid JSON object. " <> prompt)
    
    # For test purposes, we'll parse the model response into a map
    case Jason.decode(response.content) do
      {:ok, parsed} -> 
        # Return as a map with string keys
        %{"result" => parsed}
      {:error, _} -> 
        # If we can't parse as JSON, just wrap the raw text
        %{"result" => %{"text" => response.content}}
    end
  end
  
  # Create a simplified map operator
  EmberEx.Operators.MapOperator.new_with_name(
    "test_llm_op",
    nil,
    fn input ->
      # Format the prompt
      prompt = Enum.reduce(Map.to_list(input), prompt_template, fn {key, value}, acc ->
        String.replace(acc, "{#{key}}", to_string(value))
      end)
      
      # Call the model and return the result
      model_fn.(prompt)
    end
  )
end

# Test 1: Summarization
IO.puts("\n🧪 Test 1: Summarization")
summarize_op = create_test_operator.(
  "Summarize this text in {max_length} words or less: {text}",
  "openai:gpt-4o"
)

summary_input = %{
  text: "The Ember framework is a powerful tool for building AI applications using Language Models (LLMs). It provides a structured approach to building LLM applications with features like operators, graphs, and execution engines. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging the functional programming paradigm and concurrency features of the BEAM.",
  max_length: 30
}

IO.puts("Running summarization with input: #{inspect(summary_input)}")
summary_result = EmberEx.Operators.Operator.call(summarize_op, summary_input)

IO.puts("\n📝 Summarization Result:")
IO.inspect(summary_result, pretty: true)

# Test 2: Question Answering
IO.puts("\n🧪 Test 2: Question Answering")
qa_op = create_test_operator.(
  "Answer this question based on the context.\nContext: {context}\nQuestion: {question}\nRespond with a JSON object with 'answer' and 'confidence' fields.",
  "openai:gpt-4o"
)

qa_input = %{
  question: "What is the capital of France?",
  context: "France is a country in Western Europe. Its capital is Paris, which is known for its art, fashion, and culture. The Eiffel Tower is located in Paris."
}

IO.puts("Running question answering with input: #{inspect(qa_input)}")
qa_result = EmberEx.Operators.Operator.call(qa_op, qa_input)

IO.puts("\n🤔 Question Answering Result:")
IO.inspect(qa_result, pretty: true)

# Test 3: Translation
IO.puts("\n🧪 Test 3: Translation")
translate_op = create_test_operator.(
  "Translate this text from {source_language} to {target_language}: {text}\nRespond with a JSON object with 'translated_text' and 'detected_language' fields.",
  "openai:gpt-4o"
)

translate_input = %{
  text: "Hello world, how are you doing today?",
  source_language: "auto",
  target_language: "French"
}

IO.puts("Running translation with input: #{inspect(translate_input)}")
translate_result = EmberEx.Operators.Operator.call(translate_op, translate_input)

IO.puts("\n🌍 Translation Result:")
IO.inspect(translate_result, pretty: true)

IO.puts("\n✅ All tests completed!")
