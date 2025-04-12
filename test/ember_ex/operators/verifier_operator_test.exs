defmodule EmberEx.Operators.VerifierOperatorTest do
  @moduledoc """
  Tests for the VerifierOperator module.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.Operators.VerifierOperator
  alias EmberEx.Operators.Operator
  
  # TypeCheck is not available in this project
  
  describe "new/3" do
    test "creates a new verifier operator with default values" do
      length_check = fn text -> String.length(text) > 10 end
      verifier = VerifierOperator.new([length_check])
      
      assert verifier.conditions == [length_check]
      assert verifier.input_key == nil
      assert verifier.output_key == nil
    end
    
    test "creates a new verifier operator with provided values" do
      length_check = fn text -> String.length(text) > 10 end
      no_numbers = fn text -> not String.match?(text, ~r/[0-9]/) end
      
      verifier = VerifierOperator.new([length_check, no_numbers], :text, :validation_results)
      
      assert length(verifier.conditions) == 2
      assert verifier.input_key == :text
      assert verifier.output_key == :validation_results
    end
  end
  
  describe "call/2" do
    test "verifies input against conditions with raw output" do
      length_check = fn text -> String.length(text) > 10 end
      verifier = VerifierOperator.new([length_check])
      
      # Should pass
      result = Operator.call(verifier, "Hello, world!")
      assert result == %{passed: true, results: [true]}
      
      # Should fail
      result = Operator.call(verifier, "Short")
      assert result == %{passed: false, results: [false]}
    end
    
    test "verifies input against conditions with keyed output" do
      length_check = fn text -> String.length(text) > 10 end
      verifier = VerifierOperator.new([length_check], :text, :validation_results)
      
      # Should pass
      result = Operator.call(verifier, %{text: "Hello, world!"})
      assert result == %{validation_results: %{passed: true, results: [true]}}
      
      # Should fail
      result = Operator.call(verifier, %{text: "Short"})
      assert result == %{validation_results: %{passed: false, results: [false]}}
    end
    
    test "verifies input against multiple conditions" do
      length_check = fn text -> String.length(text) > 10 end
      no_numbers = fn text -> not String.match?(text, ~r/[0-9]/) end
      
      verifier = VerifierOperator.new([length_check, no_numbers])
      
      # Both conditions pass
      result = Operator.call(verifier, "Hello, world!")
      assert result == %{passed: true, results: [true, true]}
      
      # First condition passes, second fails
      result = Operator.call(verifier, "Hello, world 123!")
      assert result == %{passed: false, results: [true, false]}
      
      # Both conditions fail
      result = Operator.call(verifier, "Hi 123")
      assert result == %{passed: false, results: [false, false]}
    end
  end
  
  describe "condition/2" do
    test "creates a condition function that returns true or an error tuple" do
      is_string = VerifierOperator.condition(fn value -> is_binary(value) end, "Value must be a string")
      
      assert is_string.("Hello") == true
      assert is_string.(123) == {:error, "Value must be a string"}
    end
  end
  
  describe "not_empty/1" do
    test "creates a condition function that checks for non-empty values" do
      not_empty = VerifierOperator.not_empty("Value cannot be empty")
      
      assert not_empty.("Hello") == true
      assert not_empty.("") == {:error, "Value cannot be empty"}
      assert not_empty.(nil) == {:error, "Value cannot be empty"}
      assert not_empty.([]) == {:error, "Value cannot be empty"}
      assert not_empty.(%{}) == {:error, "Value cannot be empty"}
    end
  end
  
  describe "matches_pattern/2" do
    test "creates a condition function that checks if a value matches a regex pattern" do
      email_pattern = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
      is_email = VerifierOperator.matches_pattern(email_pattern, "Invalid email format")
      
      assert is_email.("user@example.com") == true
      assert is_email.("not-an-email") == {:error, "Invalid email format"}
      assert is_email.(123) == {:error, "Invalid email format"}
    end
  end
  
  describe "all/2" do
    test "creates a condition function that applies multiple conditions" do
      not_empty = VerifierOperator.not_empty("Value cannot be empty")
      is_string = VerifierOperator.condition(fn v -> is_binary(v) end, "Must be a string")
      
      all_conditions = VerifierOperator.all([not_empty, is_string], "Failed validation")
      
      assert all_conditions.("Hello") == true
      assert all_conditions.(nil) == {:error, "Failed validation"}
      assert all_conditions.(123) == {:error, "Failed validation"}
    end
  end
  
  describe "error handling" do
    test "handles errors in conditions gracefully" do
      # Condition that raises an error
      error_condition = fn _ -> raise "Boom!" end
      
      verifier = VerifierOperator.new([error_condition])
      
      # Should catch the error and log it
      result = Operator.call(verifier, "Hello, world!")
      assert result == %{passed: false, results: [{:error, "Verification condition error: %RuntimeError{message: \"Boom!\"}"}]}
    end
  end
end
