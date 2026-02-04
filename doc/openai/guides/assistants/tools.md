Assistants API tools

Beta

============================

Explore tools for file search, code, and function calling.

Based on your feedback from the Assistants API beta, we've incorporated key improvements into the Responses API. After we achieve full feature parity, we will announce a **deprecation plan** later this year, with a target sunset date in the first half of 2026. [Learn more](/docs/guides/responses-vs-chat-completions).

Overview
--------

Assistants created using the Assistants API can be equipped with tools that allow them to perform more complex tasks or interact with your application. We provide built-in tools for assistants, but you can also define your own tools to extend their capabilities using Function Calling.

The Assistants API currently supports the following tools:

[

File Search

Built-in RAG tool to process and search through files

](/docs/assistants/tools/file-search)[

Code Interpreter

Write and run python code, process files and diverse data

](/docs/assistants/tools/code-interpreter)[

Function Calling

Use your own custom functions to interact with your application

](/docs/assistants/tools/function-calling)

Next steps
----------

*   See the API reference to [submit tool outputs](/docs/api-reference/runs/submitToolOutputs)
    
*   Build a tool-using assistant with our [Quickstart app](https://github.com/openai/openai-assistants-quickstart)