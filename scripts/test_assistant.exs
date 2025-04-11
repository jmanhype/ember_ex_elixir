# Set the OpenAI API key
System.put_env("OPENAI_API_KEY", "YOUR_OPENAI_API_KEY_HERE")

IO.puts("Testing EmberEx with real OpenAI models")
IO.puts("======================================")

# Test 1: Summarization
IO.puts("\n🧪 Test 1: Summarization")
summary_input = %{
  type: "summarize",
  text: "The Ember framework is a powerful tool for building AI applications using Language Models (LLMs). It provides a structured approach to building LLM applications with features like operators, graphs, and execution engines. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging the functional programming paradigm and concurrency features of the BEAM."
}

IO.puts("Running summarization with input: #{inspect(summary_input)}")
summary_result = EmberEx.Examples.Assistant.run(summary_input)

IO.puts("\n📝 Summarization Result:")
IO.inspect(summary_result)
IO.puts("\nSummary: #{summary_result.result.content["summary"]}")

# Test 2: Question Answering
IO.puts("\n🧪 Test 2: Question Answering")
qa_input = %{
  type: "qa",
  question: "What is the capital of France?",
  context: "France is a country in Western Europe. Its capital is Paris, which is known for its art, fashion, and culture. The Eiffel Tower is located in Paris."
}

IO.puts("Running question answering with input: #{inspect(qa_input)}")
qa_result = EmberEx.Examples.Assistant.run(qa_input)

IO.puts("\n🤔 Question Answering Result:")
IO.inspect(qa_result)
IO.puts("\nAnswer: #{qa_result.result.content["answer"]}")
IO.puts("Confidence: #{qa_result.result.content["confidence"]}")

# Test 3: Translation
IO.puts("\n🧪 Test 3: Translation")
translate_input = %{
  type: "translate",
  text: "Hello world, how are you doing today?",
  source_language: "auto",
  target_language: "French"
}

IO.puts("Running translation with input: #{inspect(translate_input)}")
translate_result = EmberEx.Examples.Assistant.run(translate_input)

IO.puts("\n🌍 Translation Result:")
IO.inspect(translate_result)
IO.puts("\nTranslated text: #{translate_result.result.content["translated_text"]}")
IO.puts("Detected language: #{translate_result.result.content["detected_language"]}")

IO.puts("\n✅ All tests completed!")
