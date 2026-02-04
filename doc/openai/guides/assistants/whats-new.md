What's new in Assistants API

Beta

====================================

Discover new features and improvements in Assistants API.

March 2025
----------

Based on developer feedback from the Assistants API beta, we've incorporated key improvements into the [Responses API](/docs/guides/responses-vs-chat-completions), making it more flexible, faster, and easier to use.

*   We launched the Responses API, a new API primitive with built-in tools, like function calling, file search, web search, and computer use.
*   We're working to achieve full feature parity between the Assistants and the Responses API, including support for Assistant-like and Thread-like objects and the Code Interpreter tool. We will communicate updates to the Assistants API in the [changelog](/docs/changelog).
*   After achieving full feature parity, we plan to formally announce the deprecation of the Assistants API with a target sunset date in the first half of 2026. Upon deprecation, we will provide a clear migration guide from the Assistants API to the Responses API that allows developers to preserve all their data and migrate their applications.
*   Until we formally announce the deprecation, we will continue delivering new models to the Assistants API. The Responses API represents the future direction for building agents on OpenAI.

April 2024
----------

We are announcing a variety of new features and improvements to the Assistants API and moving our Beta to a new API version, `OpenAI-Beta: assistants=v2`. Here's what's new:

*   We're launching an [improved retrieval tool called `file_search`](/docs/assistants/tools/file-search), which can ingest up to 10,000 files per assistant - 500x more than before. It is faster, supports parallel queries through multi-threaded searches, and features enhanced reranking and query rewriting.
*   Alongside `file_search`, we're introducing [`vector_store` objects](/docs/assistants/tools/file-search#vector-stores) in the API. Once a file is added to a vector store, it's automatically parsed, chunked, and embedded, made ready to be searched. Vector stores can be used across assistants and threads, simplifying file management and billing.
*   You can now [control the maximum number of tokens](/docs/assistants/overview) a run uses in the Assistants API, allowing you to manage token usage costs. You can also set limits on the number of previous / recent messages used in each run.
*   We've added support for the [`tool_choice` parameter](/docs/api-reference/runs/object#runs/object-tool_choice) which can be used to force the use of a specific tool (like `file_search`, `code_interpreter`, or a `function`) in a particular run.
*   You can now [create messages with the role `assistant`](/docs/api-reference/messages/createMessage#messages-createmessage-role) to create custom conversation histories in Threads.
*   Assistant and Run objects now support popular model configuration parameters like [`temperature`](/docs/api-reference/assistants/createAssistant#assistants-createassistant-temperature), [`response_format` (JSON mode)](/docs/api-reference/assistants/createAssistant#assistants-createassistant-response_format), and [`top_p`](/docs/api-reference/assistants/createAssistant#assistants-createassistant-top_p).
*   You can now use [fine-tuned models](/docs/guides/fine-tuning) in the Assistants API. At the moment, only fine-tuned versions of `gpt-3.5-turbo-0125` are supported.
*   Assistants API now supports [streaming](/docs/assistants/overview#step-4-create-a-run?context=with-streaming).
*   We've added several streaming and polling helpers to our [Node](https://github.com/openai/openai-node/blob/master/helpers.md) and [Python](https://github.com/openai/openai-python/blob/main/helpers.md) SDKs.

See our [migration guide](/docs/assistants/migration) to learn more about how to migrate your tool usage to the latest version of the Assistants API.