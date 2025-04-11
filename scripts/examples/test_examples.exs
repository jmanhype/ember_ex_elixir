#!/usr/bin/env elixir

# This script demonstrates all the EmberEx examples

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
