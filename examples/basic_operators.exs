#!/usr/bin/env elixir
# Basic example demonstrating EmberEx core functionality
#
# This example shows:
# 1. Creating basic operators
# 2. Using operators in sequence
# 3. Running a simple computation pipeline

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.BasicOperators do
  @moduledoc """
  A minimal example demonstrating basic EmberEx operator functionality.
  """
  
  alias EmberEx.Operators.{MapOperator, SequenceOperator}
  
  @doc """
  Run the example.
  """
  def run do
    IO.puts("=== EmberEx Basic Operators Example ===\n")
    
    # Create a simple operator that uppercases text
    uppercase_op = MapOperator.new(&String.upcase/1, :text, :uppercase_text)
    
    # Create a simple operator that counts characters
    count_op = MapOperator.new(
      fn text -> String.length(text) end,
      :text,
      :char_count
    )
    
    # Call the operators with inputs
    input = %{text: "hello world"}
    
    upper_result = EmberEx.Operators.Operator.call(uppercase_op, input)
    IO.puts("Original: #{input.text}")
    IO.puts("Uppercase: #{upper_result.uppercase_text}")
    
    count_result = EmberEx.Operators.Operator.call(count_op, input)
    IO.puts("Character count: #{count_result.char_count}")
    
    # Chain operators in sequence
    IO.puts("\nSequence operator example:")
    
    # Create an operator to compute word count
    word_count_op = MapOperator.new(
      fn text -> length(String.split(text)) end,
      :text,
      :word_count
    )
    
    # Create a pipeline of operations
    pipeline = SequenceOperator.new([
      uppercase_op,
      MapOperator.new(
        fn %{uppercase_text: text} -> %{reversed: String.reverse(text)} end,
        nil,
        :reversed
      )
    ])
    
    sequence_result = EmberEx.Operators.Operator.call(pipeline, input)
    IO.puts("Original: #{input.text}")
    IO.puts("Uppercase: #{sequence_result.uppercase_text}")
    IO.puts("Reversed uppercase: #{sequence_result.reversed.reversed}")
    
    :ok
  end
end

# Run the example
EmberEx.Examples.BasicOperators.run()
