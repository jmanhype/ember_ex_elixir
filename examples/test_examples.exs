#!/usr/bin/env elixir

# This script demonstrates all the EmberEx examples

# Define missing modules if they don't exist
defmodule EmberEx.Examples.RAG do
  @moduledoc """
  Example implementation of a Retrieval Augmented Generation (RAG) system.
  """
  
  alias EmberEx.Operators.{MapOperator, SequenceOperator}
  
  @doc """
  Create a mock RAG example that demonstrates the pattern without using real LLMs.
  """
  def create_example do
    # Mock retriever that simulates document search
    retriever = MapOperator.new(fn query ->
      # Simulate retrieving documents based on query
      docs = if String.contains?(query, "Elixir") do
        ["Elixir is a functional programming language built on the Erlang VM.", 
         "Elixir provides great concurrency support and fault tolerance."]
      else
        ["No relevant documents found."]
      end
      
      %{query: query, documents: docs}
    end)
    
    # Mock generator that produces an answer based on retrieved documents
    generator = MapOperator.new(fn %{query: query, documents: docs} ->
      # Simulate generating an answer
      response = if Enum.at(docs, 0) == "No relevant documents found." do
        "I don't have enough information to answer that question."
      else
        "Elixir is a functional programming language built on the Erlang VM. " <>
        "It provides excellent concurrency support and fault tolerance, making it " <>
        "ideal for building distributed and reliable applications."
      end
      
      %{response: response, query: query, documents: docs}
    end)
    
    # Mock verifier to check answer quality
    verifier = MapOperator.new(fn %{response: response, query: query, documents: docs} ->
      # Simulate verification
      is_verified = String.length(response) > 20 && Enum.count(docs) > 0
      
      %{response: response, is_verified: is_verified}
    end)
    
    # Combine the operators into a pipeline
    SequenceOperator.new([retriever, generator, verifier])
  end
end

defmodule EmberEx.Examples.StructuredExtraction do
  @moduledoc """
  Example implementation of structured data extraction from unstructured text.
  """
  
  alias EmberEx.Operators.MapOperator
  
  @doc """
  Create a mock structured extraction example that simulates extracting resume data.
  """
  def create_example do
    MapOperator.new(fn resume_text ->
      # Simple regex-based extraction (in a real system, this would use an LLM)
      name_match = Regex.run(~r/^([\w\s]+)\n/m, resume_text)
      title_match = Regex.run(~r/^[\w\s]+\n([\w\s]+)\n/m, resume_text)
      
      experience_blocks = Regex.scan(~r/([\w\s]+) at ([\w\s]+) \((\d{4}-(?:\d{4}|Present))\)[\n-][^\n]*([^\n]+)/m, resume_text)
      experience = Enum.map(experience_blocks, fn [_, title, company, period, description] ->
        %{
          title: String.trim(title),
          company: String.trim(company),
          period: String.trim(period),
          description: String.trim(description)
        }
      end)
      
      education_blocks = Regex.scan(~r/([^,]+), ([^\(]+)\s+\((\d{4}-\d{4})\)/m, resume_text) 
      education = Enum.map(education_blocks, fn [_, degree, institution, period] ->
        %{
          degree: String.trim(degree),
          institution: String.trim(institution),
          period: String.trim(period)
        }
      end)
      
      skills_match = Regex.run(~r/SKILLS[^\n]*\n([^\n]+)/m, resume_text)
      skills = if skills_match do
        Enum.at(skills_match, 1)
        |> String.split(",")
        |> Enum.map(&String.trim/1)
      else
        []
      end
      
      # Return structured data
      %{
        personal_info: %{
          name: name_match && String.trim(Enum.at(name_match, 1)) || "Unknown",
          title: title_match && String.trim(Enum.at(title_match, 1)) || "Unknown"
        },
        experience: experience,
        education: education,
        skills: skills
      }
    end)
  end
end

defmodule EmberEx.Examples.EnsembleReasoning do
  @moduledoc """
  Example implementation of ensemble reasoning with multiple models.
  """
  
  alias EmberEx.Operators.{MapOperator, ParallelOperator, SequenceOperator}
  
  @doc """
  Create a mock ensemble reasoning example that simulates multiple models answering a question.
  """
  def create_example(ensemble_type) do
    # Create mock models that simulate different answers
    model1 = MapOperator.new(fn query ->
      # Basic answer
      answer = cond do
        String.contains?(query, "capital of France") -> "Paris is the capital of France."
        String.contains?(query, "Eiffel Tower") -> "The Eiffel Tower was built in 1889."
        true -> "I don't know the answer to that question."
      end
      
      %{model: "model1", answer: answer, confidence: 0.8}
    end)
    
    model2 = MapOperator.new(fn query ->
      # Slightly different answer
      answer = cond do
        String.contains?(query, "capital of France") -> "The capital of France is Paris."
        String.contains?(query, "Eiffel Tower") -> "Construction of the Eiffel Tower was completed in 1889 for the World's Fair."
        true -> "I don't have enough information to answer that."
      end
      
      %{model: "model2", answer: answer, confidence: 0.7}
    end)
    
    model3 = MapOperator.new(fn query ->
      # Potentially incorrect answer
      answer = cond do
        String.contains?(query, "capital of France") -> "Paris is the capital and largest city of France."
        String.contains?(query, "Eiffel Tower") -> "The Eiffel Tower was constructed between 1887 and 1889."
        true -> "I cannot provide an accurate answer to that query."
      end
      
      %{model: "model3", answer: answer, confidence: 0.9}
    end)
    
    # Run models in parallel
    parallel_models = ParallelOperator.new([model1, model2, model3])
    
    # Create an aggregator based on the ensemble type
    aggregator = case ensemble_type do
      :majority_vote ->
        MapOperator.new(fn results ->
          # Simple majority vote (in a real system, this would be more sophisticated)
          answer = results
                    |> Enum.map(&Map.get(&1, :answer))
                    |> Enum.max_by(fn a -> Enum.count(results, &(Map.get(&1, :answer) == a)) end)
          
          confidence = Enum.count(results, &(Map.get(&1, :answer) == answer)) / Enum.count(results)
          
          %{answer: answer, confidence: confidence}
        end)
      
      :judge_selection ->
        MapOperator.new(fn results ->
          # Select the answer with highest confidence
          highest_conf_result = Enum.max_by(results, &Map.get(&1, :confidence))
          
          %{answer: highest_conf_result.answer, confidence: highest_conf_result.confidence}
        end)
    end
    
    # Create mapper to handle input
    input_mapper = MapOperator.new(fn query ->
      # Pass the query to each model
      [query, query, query]
    end)
    
    # Build the full pipeline
    SequenceOperator.new([
      input_mapper,
      parallel_models,
      aggregator
    ])
  end
end

defmodule EmberEx.Examples.InstructorValidation do
  @moduledoc """
  Example implementation of structured validation using schema-based validation.
  """
  
  alias EmberEx.Operators.MapOperator
  
  @doc """
  Create a mock validation example that simulates extracting structured data from a product review.
  """
  def create_example do
    MapOperator.new(fn review_text ->
      # Extract review information (in a real system, this would use an LLM with validation)
      product_match = Regex.run(~r/The ([\w\s]+) is/, review_text)
      rating_match = Regex.run(~r/(\d+)\/5/, review_text)
      
      # Determine sentiment
      sentiment = cond do
        String.contains?(review_text, "great") -> "positive"
        String.contains?(review_text, "good") -> "positive"
        String.contains?(review_text, "excellent") -> "positive"
        String.contains?(review_text, "poor") -> "negative"
        String.contains?(review_text, "bad") -> "negative"
        String.contains?(review_text, "terrible") -> "negative"
        true -> "neutral"
      end
      
      # Extract key points
      key_points = []
      |> then(fn points ->
        if String.contains?(review_text, "Battery") || String.contains?(review_text, "battery"), 
          do: points ++ ["Battery life"], else: points
      end)
      |> then(fn points ->
        if String.contains?(review_text, "tracking"), 
          do: points ++ ["Tracking accuracy"], else: points
      end)
      |> then(fn points ->
        if String.contains?(review_text, "app"), 
          do: points ++ ["App experience"], else: points
      end)
      
      # Determine improvement suggestions
      improvement_suggestions = []
      |> then(fn sugg ->
        if String.contains?(review_text, "clunky") || String.contains?(review_text, "could be better"), 
          do: sugg ++ ["Improve user interface"], else: sugg
      end)
      
      # Return structured data
      %{
        review: %{
          product_name: product_match && String.trim(Enum.at(product_match, 1)) || "Unknown",
          rating: rating_match && String.to_integer(Enum.at(rating_match, 1)) || 0,
          sentiment: sentiment
        },
        key_points: key_points,
        improvement_suggestions: improvement_suggestions,
        audience: "Tech enthusiasts"
      }
    end)
  end
end

IO.puts("\n\n=== Running RAG Example ===")
rag_example = EmberEx.Examples.RAG.create_example()
result = EmberEx.Operators.Operator.call(rag_example, "What is Elixir?")
IO.puts("Query: What is Elixir?")
IO.puts("Response: #{inspect(result[:response])}")
IO.puts("Is verified: #{inspect(result[:is_verified])}")

IO.puts("\n\n=== Running Structured Extraction Example ===")
extraction_example = EmberEx.Examples.StructuredExtraction.create_example()
resume_text = """
John Smith
Software Engineer

EXPERIENCE
Senior Developer at Tech Company (2018-Present)
- Implemented microservices architecture
- Led team of 5 developers
- Reduced system latency by 30%

Junior Developer at Startup (2015-2018)
- Full-stack development with React and Node.js
- Implemented CI/CD pipeline

EDUCATION
Computer Science, University of Technology (2011-2015)
- GPA: 3.8/4.0
- Thesis: "Optimizing Database Performance"

SKILLS
Programming: JavaScript, Python, Java, Elixir
Tools: Docker, Kubernetes, Git
"""
result = EmberEx.Operators.Operator.call(extraction_example, resume_text)
IO.puts("Resume extraction results:")
IO.puts("Name: #{result.personal_info.name}")
IO.puts("Title: #{result.personal_info.title}")
IO.puts("Experience entries: #{length(result.experience)}")
IO.puts("Education entries: #{length(result.education)}")
IO.puts("Skills: #{Enum.join(result.skills, ", ")}")

IO.puts("\n\n=== Running Ensemble Reasoning Example ===")
ensemble = EmberEx.Examples.EnsembleReasoning.create_example(:majority_vote)
result = EmberEx.Operators.Operator.call(ensemble, "What is the capital of France?")
IO.puts("Query: What is the capital of France?")
IO.puts("Majority vote answer: #{result.answer}")
IO.puts("Confidence: #{result.confidence}")

ensemble_judge = EmberEx.Examples.EnsembleReasoning.create_example(:judge_selection)
result = EmberEx.Operators.Operator.call(ensemble_judge, "When was the Eiffel Tower built?")
IO.puts("\nQuery: When was the Eiffel Tower built?")
IO.puts("Judge selection answer: #{result.answer}")
IO.puts("Confidence: #{result.confidence}")

IO.puts("\n\n=== Running Instructor Validation Example ===")
analyzer = EmberEx.Examples.InstructorValidation.create_example()
review_text = "The SmartWatch X is great. Battery lasts 3 days and tracking is accurate. The app is a bit clunky though. 4/5."
result = EmberEx.Operators.Operator.call(analyzer, review_text)
IO.puts("Review: #{review_text}")
IO.puts("Extracted product: #{result.review.product_name}")
IO.puts("Rating: #{result.review.rating}/5")
IO.puts("Sentiment: #{result.review.sentiment}")
IO.puts("Key points: #{inspect(result.key_points)}")
IO.puts("Improvement suggestions: #{inspect(result.improvement_suggestions)}")
IO.puts("Target audience: #{result.audience}")
