# Create a model response

`POST` `/responses`

Creates a model response. Provide [text](/docs/guides/text) or
[image](/docs/guides/images) inputs to generate [text](/docs/guides/text)
or [JSON](/docs/guides/structured-outputs) outputs. Have the model call
your own [custom code](/docs/guides/function-calling) or use built-in
[tools](/docs/guides/tools) like [web search](/docs/guides/tools-web-search)
or [file search](/docs/guides/tools-file-search) to use your own data
as input for the model's response.


## Request Body

### Content Type: `application/json`

**Type**: object (19 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `metadata` | map | No |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `temperature` | number | No | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
| `top_p` | number | No | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
| `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
| `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
| `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
| `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
| `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|   ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
| `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
| `instructions` | string | No |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
| `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
| `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | No |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
| `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | No |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
| `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
| `input` | oneOf: string | array of oneOf: object (3 properties) | object | object (2 properties) | Yes |  |  | Text, image, or file inputs to the model, used to generate a response. <br>  <br> Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Image inputs](/docs/guides/images) <br> - [File inputs](/docs/guides/pdf-files) <br> - [Conversation state](/docs/guides/conversation-state) <br> - [Function calling](/docs/guides/function-calling) <br>  |
| `include` | array of string | No |  |  | Specify additional output data to include in the model response. Currently <br> supported values are: <br> - `file_search_call.results`: Include the search results of <br>   the file search tool call. <br> - `message.input_image.image_url`: Include image urls from the input message. <br> - `computer_call_output.output.image_url`: Include image urls from the computer call output. <br> - `reasoning.encrypted_content`: Includes an encrypted version of reasoning  <br>   tokens in reasoning item outputs. This enables reasoning items to be used in <br>   multi-turn conversations when using the Responses API statelessly (like <br>   when the `store` parameter is set to `false`, or when an organization is <br>   enrolled in the zero data retention program). <br>  |
| `parallel_tool_calls` | boolean | No | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
| `store` | boolean | No | `true` |  | Whether to store the generated model response for later retrieval via <br> API. <br>  |
| `stream` | boolean | No | `false` |  | If set to true, the model response data will be streamed to the client <br> as it is generated using [server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#Event_stream_format). <br> See the [Streaming section below](/docs/api-reference/responses-streaming) <br> for more information. <br>  |


### Items in `include` array

Each item is of type `string`. Allowed values: `file_search_call.results`, `message.input_image.image_url`, `computer_call_output.output.image_url`, `reasoning.encrypted_content` - Specify additional output data to include in the model response. Currently
supported values are:
- `file_search_call.results`: Include the search results of
  the file search tool call.
- `message.input_image.image_url`: Include image urls from the input message.
- `computer_call_output.output.image_url`: Include image urls from the computer call output.
- `reasoning.encrypted_content`: Includes an encrypted version of reasoning 
  tokens in reasoning item outputs. This enables reasoning items to be used in
  multi-turn conversations when using the Responses API statelessly (like
  when the `store` parameter is set to `false`, or when an organization is
  enrolled in the zero data retention program).


## Responses

### 200 - OK

#### Content Type: `application/json`

#### The response object

**Type**: object (24 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `temperature` | number | Yes | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
| `top_p` | number | Yes | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
| `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
| `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
| `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
| `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
| `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|   ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
| `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
| `instructions` | string | Yes |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
| `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
| `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | Yes |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
| `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | Yes |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
| `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
| `id` | string | Yes |  |  | Unique identifier for this Response. <br>  |
| `object` | string | Yes |  | `response` | The object type of this resource - always set to `response`. <br>  |
| `status` | string | No |  | `completed`, `failed`, `in_progress`, `incomplete` | The status of the response generation. One of `completed`, `failed`,  <br> `in_progress`, or `incomplete`. <br>  |
| `created_at` | number | Yes |  |  | Unix timestamp (in seconds) of when this Response was created. <br>  |
| `error` | object (2 properties) | Yes |  |  | An error object returned when the model fails to generate a Response. <br>  |
| `incomplete_details` | object (1 property) | Yes |  |  | Details about why the response is incomplete. <br>  |
| `output` | array of anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | An array of content items generated by the model. <br>  <br> - The length and order of items in the `output` array is dependent <br>   on the model's response. <br> - Rather than accessing the first item in the `output` array and  <br>   assuming it's an `assistant` message with the content generated by <br>   the model, you might consider using the `output_text` property where <br>   supported in SDKs. <br>  |
| `output_text` | string | No |  |  | SDK-only convenience property that contains the aggregated text output  <br> from all `output_text` items in the `output` array, if any are present.  <br> Supported in the Python and JavaScript SDKs. <br>  |
| `usage` | object (5 properties) | No |  |  | Represents token usage details including input tokens, output tokens, <br> a breakdown of output tokens, and the total tokens used. <br>  |
|   ↳ `output_tokens` | integer | Yes |  |  | The number of output tokens. |
|   ↳ `output_tokens_details` | object (1 property) | Yes |  |  | A detailed breakdown of the output tokens. |
|   ↳ `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
| `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
**Example:**

```json
{
  "id": "resp_67ccd3a9da748190baa7f1570fe91ac604becb25c45c1d41",
  "object": "response",
  "created_at": 1741476777,
  "status": "completed",
  "error": null,
  "incomplete_details": null,
  "instructions": null,
  "max_output_tokens": null,
  "model": "gpt-4o-2024-08-06",
  "output": [
    {
      "type": "message",
      "id": "msg_67ccd3acc8d48190a77525dc6de64b4104becb25c45c1d41",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "The image depicts a scenic landscape with a wooden boardwalk or pathway leading through lush, green grass under a blue sky with some clouds. The setting suggests a peaceful natural area, possibly a park or nature reserve. There are trees and shrubs in the background.",
          "annotations": []
        }
      ]
    }
  ],
  "parallel_tool_calls": true,
  "previous_response_id": null,
  "reasoning": {
    "effort": null,
    "summary": null
  },
  "store": true,
  "temperature": 1,
  "text": {
    "format": {
      "type": "text"
    }
  },
  "tool_choice": "auto",
  "tools": [],
  "top_p": 1,
  "truncation": "disabled",
  "usage": {
    "input_tokens": 328,
    "input_tokens_details": {
      "cached_tokens": 0
    },
    "output_tokens": 52,
    "output_tokens_details": {
      "reasoning_tokens": 0
    },
    "total_tokens": 380
  },
  "user": null,
  "metadata": {}
}
```

#### Content Type: `text/event-stream`

**Any of the following:**

##### Option 1:

**Type**: object (2 properties)

Emitted when there is a partial audio response.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.audio.delta` | The type of the event. Always `response.audio.delta`. <br>  |
| `delta` | string | Yes |  |  | A chunk of Base64 encoded response audio bytes. <br>  |
**Example:**

```json
{
  "type": "response.audio.delta",
  "response_id": "resp_123",
  "delta": "base64encoded..."
}

```

##### Option 2:

**Type**: object (1 property)

Emitted when the audio response is complete.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.audio.done` | The type of the event. Always `response.audio.done`. <br>  |
**Example:**

```json
{
  "type": "response.audio.done",
  "response_id": "resp-123"
}

```

##### Option 3:

**Type**: object (2 properties)

Emitted when there is a partial transcript of audio.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.audio.transcript.delta` | The type of the event. Always `response.audio.transcript.delta`. <br>  |
| `delta` | string | Yes |  |  | The partial transcript of the audio response. <br>  |
**Example:**

```json
{
  "type": "response.audio.transcript.delta",
  "response_id": "resp_123",
  "delta": " ... partial transcript ... "
}

```

##### Option 4:

**Type**: object (1 property)

Emitted when the full audio transcript is completed.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.audio.transcript.done` | The type of the event. Always `response.audio.transcript.done`. <br>  |
**Example:**

```json
{
  "type": "response.audio.transcript.done",
  "response_id": "resp_123"
}

```

##### Option 5:

**Type**: object (3 properties)

Emitted when a partial code snippet is added by the code interpreter.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.code_interpreter_call.code.delta` | The type of the event. Always `response.code_interpreter_call.code.delta`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the code interpreter call is in progress. <br>  |
| `delta` | string | Yes |  |  | The partial code snippet added by the code interpreter. <br>  |
**Example:**

```json
{
  "type": "response.code_interpreter_call.code.delta",
  "response_id": "resp-123",
  "output_index": 0,
  "delta": "partial code"
}

```

##### Option 6:

**Type**: object (3 properties)

Emitted when code snippet output is finalized by the code interpreter.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.code_interpreter_call.code.done` | The type of the event. Always `response.code_interpreter_call.code.done`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the code interpreter call is in progress. <br>  |
| `code` | string | Yes |  |  | The final code snippet output by the code interpreter. <br>  |
**Example:**

```json
{
  "type": "response.code_interpreter_call.code.done",
  "response_id": "resp-123",
  "output_index": 3,
  "code": "console.log('done');"
}

```

##### Option 7:

**Type**: object (3 properties)

Emitted when the code interpreter call is completed.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.code_interpreter_call.completed` | The type of the event. Always `response.code_interpreter_call.completed`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the code interpreter call is in progress. <br>  |
| `code_interpreter_call` | object (5 properties) | Yes |  |  | A tool call to run code. <br>  |
|   ↳ `code` | string | Yes |  |  | The code to run. <br>  |
|   ↳ `status` | string | Yes |  | `in_progress`, `interpreting`, `completed` | The status of the code interpreter tool call. <br>  |
|   ↳ `results` | array of oneOf: object (2 properties) | object (2 properties) | Yes |  |  | The results of the code interpreter tool call. <br>  |
**Example:**

```json
{
  "type": "response.code_interpreter_call.completed",
  "response_id": "resp-123",
  "output_index": 5,
  "code_interpreter_call": {}
}

```

##### Option 8:

**Type**: object (3 properties)

Emitted when a code interpreter call is in progress.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.code_interpreter_call.in_progress` | The type of the event. Always `response.code_interpreter_call.in_progress`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the code interpreter call is in progress. <br>  |
| `code_interpreter_call` | object (5 properties) | Yes |  |  | A tool call to run code. <br>  |
|   ↳ `code` | string | Yes |  |  | The code to run. <br>  |
|   ↳ `status` | string | Yes |  | `in_progress`, `interpreting`, `completed` | The status of the code interpreter tool call. <br>  |
|   ↳ `results` | array of oneOf: object (2 properties) | object (2 properties) | Yes |  |  | The results of the code interpreter tool call. <br>  |
**Example:**

```json
{
  "type": "response.code_interpreter_call.in.progress",
  "response_id": "resp-123",
  "output_index": 0,
  "code_interpreter_call": {}
}

```

##### Option 9:

**Type**: object (3 properties)

Emitted when the code interpreter is actively interpreting the code snippet.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.code_interpreter_call.interpreting` | The type of the event. Always `response.code_interpreter_call.interpreting`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the code interpreter call is in progress. <br>  |
| `code_interpreter_call` | object (5 properties) | Yes |  |  | A tool call to run code. <br>  |
|   ↳ `code` | string | Yes |  |  | The code to run. <br>  |
|   ↳ `status` | string | Yes |  | `in_progress`, `interpreting`, `completed` | The status of the code interpreter tool call. <br>  |
|   ↳ `results` | array of oneOf: object (2 properties) | object (2 properties) | Yes |  |  | The results of the code interpreter tool call. <br>  |
**Example:**

```json
{
  "type": "response.code_interpreter_call.interpreting",
  "response_id": "resp-123",
  "output_index": 4,
  "code_interpreter_call": {}
}

```

##### Option 10:

**Type**: object (2 properties)

Emitted when the model response is complete.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.completed` | The type of the event. Always `response.completed`. <br>  |
| `response` | object (24 properties) | Yes |  |  | Properties of the completed response. <br>  |
|   ↳ `temperature` | number | Yes | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
|   ↳ `top_p` | number | Yes | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
|   ↳ `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
|   ↳ `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
|   ↳ `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
|   ↳ `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
|   ↳ `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|     ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
|   ↳ `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
|   ↳ `instructions` | string | Yes |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
|   ↳ `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
|   ↳ `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | Yes |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
|   ↳ `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | Yes |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
|   ↳ `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
|   ↳ `id` | string | Yes |  |  | Unique identifier for this Response. <br>  |
|   ↳ `object` | string | Yes |  | `response` | The object type of this resource - always set to `response`. <br>  |
|   ↳ `status` | string | No |  | `completed`, `failed`, `in_progress`, `incomplete` | The status of the response generation. One of `completed`, `failed`,  <br> `in_progress`, or `incomplete`. <br>  |
|   ↳ `created_at` | number | Yes |  |  | Unix timestamp (in seconds) of when this Response was created. <br>  |
|   ↳ `error` | object (2 properties) | Yes |  |  | An error object returned when the model fails to generate a Response. <br>  |
|   ↳ `incomplete_details` | object (1 property) | Yes |  |  | Details about why the response is incomplete. <br>  |
|   ↳ `output` | array of anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | An array of content items generated by the model. <br>  <br> - The length and order of items in the `output` array is dependent <br>   on the model's response. <br> - Rather than accessing the first item in the `output` array and  <br>   assuming it's an `assistant` message with the content generated by <br>   the model, you might consider using the `output_text` property where <br>   supported in SDKs. <br>  |
|   ↳ `output_text` | string | No |  |  | SDK-only convenience property that contains the aggregated text output  <br> from all `output_text` items in the `output` array, if any are present.  <br> Supported in the Python and JavaScript SDKs. <br>  |
|   ↳ `usage` | object (5 properties) | No |  |  | Represents token usage details including input tokens, output tokens, <br> a breakdown of output tokens, and the total tokens used. <br>  |
|     ↳ `output_tokens` | integer | Yes |  |  | The number of output tokens. |
|     ↳ `output_tokens_details` | object (1 property) | Yes |  |  | A detailed breakdown of the output tokens. |
|     ↳ `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
|   ↳ `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
**Example:**

```json
{
  "type": "response.completed",
  "response": {
    "id": "resp_123",
    "object": "response",
    "created_at": 1740855869,
    "status": "completed",
    "error": null,
    "incomplete_details": null,
    "input": [],
    "instructions": null,
    "max_output_tokens": null,
    "model": "gpt-4o-mini-2024-07-18",
    "output": [
      {
        "id": "msg_123",
        "type": "message",
        "role": "assistant",
        "content": [
          {
            "type": "output_text",
            "text": "In a shimmering forest under a sky full of stars, a lonely unicorn named Lila discovered a hidden pond that glowed with moonlight. Every night, she would leave sparkling, magical flowers by the water's edge, hoping to share her beauty with others. One enchanting evening, she woke to find a group of friendly animals gathered around, eager to be friends and share in her magic.",
            "annotations": []
          }
        ]
      }
    ],
    "previous_response_id": null,
    "reasoning_effort": null,
    "store": false,
    "temperature": 1,
    "text": {
      "format": {
        "type": "text"
      }
    },
    "tool_choice": "auto",
    "tools": [],
    "top_p": 1,
    "truncation": "disabled",
    "usage": {
      "input_tokens": 0,
      "output_tokens": 0,
      "output_tokens_details": {
        "reasoning_tokens": 0
      },
      "total_tokens": 0
    },
    "user": null,
    "metadata": {}
  }
}

```

##### Option 11:

**Type**: object (5 properties)

Emitted when a new content part is added.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.content_part.added` | The type of the event. Always `response.content_part.added`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the content part was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the content part was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that was added. <br>  |
| `part` | oneOf: object (3 properties) | object (2 properties) | Yes |  |  | The content part that was added. <br>  |
**Example:**

```json
{
  "type": "response.content_part.added",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "part": {
    "type": "output_text",
    "text": "",
    "annotations": []
  }
}

```

##### Option 12:

**Type**: object (5 properties)

Emitted when a content part is done.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.content_part.done` | The type of the event. Always `response.content_part.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the content part was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the content part was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that is done. <br>  |
| `part` | oneOf: object (3 properties) | object (2 properties) | Yes |  |  | The content part that is done. <br>  |
**Example:**

```json
{
  "type": "response.content_part.done",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "part": {
    "type": "output_text",
    "text": "In a shimmering forest under a sky full of stars, a lonely unicorn named Lila discovered a hidden pond that glowed with moonlight. Every night, she would leave sparkling, magical flowers by the water's edge, hoping to share her beauty with others. One enchanting evening, she woke to find a group of friendly animals gathered around, eager to be friends and share in her magic.",
    "annotations": []
  }
}

```

##### Option 13:

**Type**: object (2 properties)

An event that is emitted when a response is created.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.created` | The type of the event. Always `response.created`. <br>  |
| `response` | object (24 properties) | Yes |  |  | The response that was created. <br>  |
|   ↳ `temperature` | number | Yes | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
|   ↳ `top_p` | number | Yes | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
|   ↳ `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
|   ↳ `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
|   ↳ `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
|   ↳ `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
|   ↳ `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|     ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
|   ↳ `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
|   ↳ `instructions` | string | Yes |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
|   ↳ `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
|   ↳ `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | Yes |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
|   ↳ `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | Yes |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
|   ↳ `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
|   ↳ `id` | string | Yes |  |  | Unique identifier for this Response. <br>  |
|   ↳ `object` | string | Yes |  | `response` | The object type of this resource - always set to `response`. <br>  |
|   ↳ `status` | string | No |  | `completed`, `failed`, `in_progress`, `incomplete` | The status of the response generation. One of `completed`, `failed`,  <br> `in_progress`, or `incomplete`. <br>  |
|   ↳ `created_at` | number | Yes |  |  | Unix timestamp (in seconds) of when this Response was created. <br>  |
|   ↳ `error` | object (2 properties) | Yes |  |  | An error object returned when the model fails to generate a Response. <br>  |
|   ↳ `incomplete_details` | object (1 property) | Yes |  |  | Details about why the response is incomplete. <br>  |
|   ↳ `output` | array of anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | An array of content items generated by the model. <br>  <br> - The length and order of items in the `output` array is dependent <br>   on the model's response. <br> - Rather than accessing the first item in the `output` array and  <br>   assuming it's an `assistant` message with the content generated by <br>   the model, you might consider using the `output_text` property where <br>   supported in SDKs. <br>  |
|   ↳ `output_text` | string | No |  |  | SDK-only convenience property that contains the aggregated text output  <br> from all `output_text` items in the `output` array, if any are present.  <br> Supported in the Python and JavaScript SDKs. <br>  |
|   ↳ `usage` | object (5 properties) | No |  |  | Represents token usage details including input tokens, output tokens, <br> a breakdown of output tokens, and the total tokens used. <br>  |
|     ↳ `output_tokens` | integer | Yes |  |  | The number of output tokens. |
|     ↳ `output_tokens_details` | object (1 property) | Yes |  |  | A detailed breakdown of the output tokens. |
|     ↳ `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
|   ↳ `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
**Example:**

```json
{
  "type": "response.created",
  "response": {
    "id": "resp_67ccfcdd16748190a91872c75d38539e09e4d4aac714747c",
    "object": "response",
    "created_at": 1741487325,
    "status": "in_progress",
    "error": null,
    "incomplete_details": null,
    "instructions": null,
    "max_output_tokens": null,
    "model": "gpt-4o-2024-08-06",
    "output": [],
    "parallel_tool_calls": true,
    "previous_response_id": null,
    "reasoning": {
      "effort": null,
      "summary": null
    },
    "store": true,
    "temperature": 1,
    "text": {
      "format": {
        "type": "text"
      }
    },
    "tool_choice": "auto",
    "tools": [],
    "top_p": 1,
    "truncation": "disabled",
    "usage": null,
    "user": null,
    "metadata": {}
  }
}

```

##### Option 14:

**Type**: object (4 properties)

Emitted when an error occurs.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `error` | The type of the event. Always `error`. <br>  |
| `code` | string | Yes |  |  | The error code. <br>  |
| `message` | string | Yes |  |  | The error message. <br>  |
| `param` | string | Yes |  |  | The error parameter. <br>  |
**Example:**

```json
{
  "type": "error",
  "code": "ERR_SOMETHING",
  "message": "Something went wrong",
  "param": null
}

```

##### Option 15:

**Type**: object (3 properties)

Emitted when a file search call is completed (results found).

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.file_search_call.completed` | The type of the event. Always `response.file_search_call.completed`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the file search call is initiated. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the file search call is initiated. <br>  |
**Example:**

```json
{
  "type": "response.file_search_call.completed",
  "output_index": 0,
  "item_id": "fs_123",
}

```

##### Option 16:

**Type**: object (3 properties)

Emitted when a file search call is initiated.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.file_search_call.in_progress` | The type of the event. Always `response.file_search_call.in_progress`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the file search call is initiated. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the file search call is initiated. <br>  |
**Example:**

```json
{
  "type": "response.file_search_call.in_progress",
  "output_index": 0,
  "item_id": "fs_123",
}

```

##### Option 17:

**Type**: object (3 properties)

Emitted when a file search is currently searching.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.file_search_call.searching` | The type of the event. Always `response.file_search_call.searching`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the file search call is searching. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the file search call is initiated. <br>  |
**Example:**

```json
{
  "type": "response.file_search_call.searching",
  "output_index": 0,
  "item_id": "fs_123",
}

```

##### Option 18:

**Type**: object (4 properties)

Emitted when there is a partial function-call arguments delta.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.function_call_arguments.delta` | The type of the event. Always `response.function_call_arguments.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the function-call arguments delta is added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the function-call arguments delta is added to. <br>  |
| `delta` | string | Yes |  |  | The function-call arguments delta that is added. <br>  |
**Example:**

```json
{
  "type": "response.function_call_arguments.delta",
  "item_id": "item-abc",
  "output_index": 0,
  "delta": "{ \"arg\":"
}

```

##### Option 19:

**Type**: object (4 properties)

Emitted when function-call arguments are finalized.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.function_call_arguments.done` |  |
| `item_id` | string | Yes |  |  | The ID of the item. |
| `output_index` | integer | Yes |  |  | The index of the output item. |
| `arguments` | string | Yes |  |  | The function-call arguments. |
**Example:**

```json
{
  "type": "response.function_call_arguments.done",
  "item_id": "item-abc",
  "output_index": 1,
  "arguments": "{ \"arg\": 123 }"
}

```

##### Option 20:

**Type**: object (2 properties)

Emitted when the response is in progress.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.in_progress` | The type of the event. Always `response.in_progress`. <br>  |
| `response` | object (24 properties) | Yes |  |  | The response that is in progress. <br>  |
|   ↳ `temperature` | number | Yes | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
|   ↳ `top_p` | number | Yes | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
|   ↳ `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
|   ↳ `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
|   ↳ `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
|   ↳ `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
|   ↳ `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|     ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
|   ↳ `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
|   ↳ `instructions` | string | Yes |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
|   ↳ `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
|   ↳ `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | Yes |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
|   ↳ `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | Yes |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
|   ↳ `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
|   ↳ `id` | string | Yes |  |  | Unique identifier for this Response. <br>  |
|   ↳ `object` | string | Yes |  | `response` | The object type of this resource - always set to `response`. <br>  |
|   ↳ `status` | string | No |  | `completed`, `failed`, `in_progress`, `incomplete` | The status of the response generation. One of `completed`, `failed`,  <br> `in_progress`, or `incomplete`. <br>  |
|   ↳ `created_at` | number | Yes |  |  | Unix timestamp (in seconds) of when this Response was created. <br>  |
|   ↳ `error` | object (2 properties) | Yes |  |  | An error object returned when the model fails to generate a Response. <br>  |
|   ↳ `incomplete_details` | object (1 property) | Yes |  |  | Details about why the response is incomplete. <br>  |
|   ↳ `output` | array of anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | An array of content items generated by the model. <br>  <br> - The length and order of items in the `output` array is dependent <br>   on the model's response. <br> - Rather than accessing the first item in the `output` array and  <br>   assuming it's an `assistant` message with the content generated by <br>   the model, you might consider using the `output_text` property where <br>   supported in SDKs. <br>  |
|   ↳ `output_text` | string | No |  |  | SDK-only convenience property that contains the aggregated text output  <br> from all `output_text` items in the `output` array, if any are present.  <br> Supported in the Python and JavaScript SDKs. <br>  |
|   ↳ `usage` | object (5 properties) | No |  |  | Represents token usage details including input tokens, output tokens, <br> a breakdown of output tokens, and the total tokens used. <br>  |
|     ↳ `output_tokens` | integer | Yes |  |  | The number of output tokens. |
|     ↳ `output_tokens_details` | object (1 property) | Yes |  |  | A detailed breakdown of the output tokens. |
|     ↳ `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
|   ↳ `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
**Example:**

```json
{
  "type": "response.in_progress",
  "response": {
    "id": "resp_67ccfcdd16748190a91872c75d38539e09e4d4aac714747c",
    "object": "response",
    "created_at": 1741487325,
    "status": "in_progress",
    "error": null,
    "incomplete_details": null,
    "instructions": null,
    "max_output_tokens": null,
    "model": "gpt-4o-2024-08-06",
    "output": [],
    "parallel_tool_calls": true,
    "previous_response_id": null,
    "reasoning": {
      "effort": null,
      "summary": null
    },
    "store": true,
    "temperature": 1,
    "text": {
      "format": {
        "type": "text"
      }
    },
    "tool_choice": "auto",
    "tools": [],
    "top_p": 1,
    "truncation": "disabled",
    "usage": null,
    "user": null,
    "metadata": {}
  }
}

```

##### Option 21:

**Type**: object (2 properties)

An event that is emitted when a response fails.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.failed` | The type of the event. Always `response.failed`. <br>  |
| `response` | object (24 properties) | Yes |  |  | The response that failed. <br>  |
|   ↳ `temperature` | number | Yes | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
|   ↳ `top_p` | number | Yes | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
|   ↳ `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
|   ↳ `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
|   ↳ `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
|   ↳ `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
|   ↳ `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|     ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
|   ↳ `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
|   ↳ `instructions` | string | Yes |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
|   ↳ `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
|   ↳ `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | Yes |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
|   ↳ `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | Yes |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
|   ↳ `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
|   ↳ `id` | string | Yes |  |  | Unique identifier for this Response. <br>  |
|   ↳ `object` | string | Yes |  | `response` | The object type of this resource - always set to `response`. <br>  |
|   ↳ `status` | string | No |  | `completed`, `failed`, `in_progress`, `incomplete` | The status of the response generation. One of `completed`, `failed`,  <br> `in_progress`, or `incomplete`. <br>  |
|   ↳ `created_at` | number | Yes |  |  | Unix timestamp (in seconds) of when this Response was created. <br>  |
|   ↳ `error` | object (2 properties) | Yes |  |  | An error object returned when the model fails to generate a Response. <br>  |
|   ↳ `incomplete_details` | object (1 property) | Yes |  |  | Details about why the response is incomplete. <br>  |
|   ↳ `output` | array of anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | An array of content items generated by the model. <br>  <br> - The length and order of items in the `output` array is dependent <br>   on the model's response. <br> - Rather than accessing the first item in the `output` array and  <br>   assuming it's an `assistant` message with the content generated by <br>   the model, you might consider using the `output_text` property where <br>   supported in SDKs. <br>  |
|   ↳ `output_text` | string | No |  |  | SDK-only convenience property that contains the aggregated text output  <br> from all `output_text` items in the `output` array, if any are present.  <br> Supported in the Python and JavaScript SDKs. <br>  |
|   ↳ `usage` | object (5 properties) | No |  |  | Represents token usage details including input tokens, output tokens, <br> a breakdown of output tokens, and the total tokens used. <br>  |
|     ↳ `output_tokens` | integer | Yes |  |  | The number of output tokens. |
|     ↳ `output_tokens_details` | object (1 property) | Yes |  |  | A detailed breakdown of the output tokens. |
|     ↳ `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
|   ↳ `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
**Example:**

```json
{
  "type": "response.failed",
  "response": {
    "id": "resp_123",
    "object": "response",
    "created_at": 1740855869,
    "status": "failed",
    "error": {
      "code": "server_error",
      "message": "The model failed to generate a response."
    },
    "incomplete_details": null,
    "instructions": null,
    "max_output_tokens": null,
    "model": "gpt-4o-mini-2024-07-18",
    "output": [],
    "previous_response_id": null,
    "reasoning_effort": null,
    "store": false,
    "temperature": 1,
    "text": {
      "format": {
        "type": "text"
      }
    },
    "tool_choice": "auto",
    "tools": [],
    "top_p": 1,
    "truncation": "disabled",
    "usage": null,
    "user": null,
    "metadata": {}
  }
}

```

##### Option 22:

**Type**: object (2 properties)

An event that is emitted when a response finishes as incomplete.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.incomplete` | The type of the event. Always `response.incomplete`. <br>  |
| `response` | object (24 properties) | Yes |  |  | The response that was incomplete. <br>  |
|   ↳ `temperature` | number | Yes | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
|   ↳ `top_p` | number | Yes | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
|   ↳ `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
|   ↳ `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
|   ↳ `previous_response_id` | string | No |  |  | The unique ID of the previous response to the model. Use this to <br> create multi-turn conversations. Learn more about  <br> [conversation state](/docs/guides/conversation-state). <br>  |
|   ↳ `model` | anyOf: anyOf: string | string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
|   ↳ `reasoning` | object (3 properties) | No |  |  | **o-series models only** <br>  <br> Configuration options for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br>  |
|     ↳ `generate_summary` | string | No |  | `auto`, `concise`, `detailed` | **Deprecated:** use `summary` instead. <br>  <br> A summary of the reasoning performed by the model. This can be <br> useful for debugging and understanding the model's reasoning process. <br> One of `auto`, `concise`, or `detailed`. <br>  |
|   ↳ `max_output_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a response, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
|   ↳ `instructions` | string | Yes |  |  | Inserts a system (or developer) message as the first item in the model's context. <br>  <br> When using along with `previous_response_id`, the instructions from a previous <br> response will not be carried over to the next response. This makes it simple <br> to swap out system (or developer) messages in new responses. <br>  |
|   ↳ `text` | object (1 property) | No |  |  | Configuration options for a text response from the model. Can be plain <br> text or structured JSON data. Learn more: <br> - [Text inputs and outputs](/docs/guides/text) <br> - [Structured Outputs](/docs/guides/structured-outputs) <br>  |
|   ↳ `tools` | array of oneOf: object (5 properties) | object (5 properties) | object (3 properties) | object (4 properties) | Yes |  |  | An array of tools the model may call while generating a response. You  <br> can specify which tool to use by setting the `tool_choice` parameter. <br>  <br> The two categories of tools you can provide the model are: <br>  <br> - **Built-in tools**: Tools that are provided by OpenAI that extend the <br>   model's capabilities, like [web search](/docs/guides/tools-web-search) <br>   or [file search](/docs/guides/tools-file-search). Learn more about <br>   [built-in tools](/docs/guides/tools). <br> - **Function calls (custom tools)**: Functions that are defined by you, <br>   enabling the model to call your own code. Learn more about <br>   [function calling](/docs/guides/function-calling). <br>  |
|   ↳ `tool_choice` | oneOf: string | object (1 property) | object (2 properties) | Yes |  |  | How the model should select which tool (or tools) to use when generating <br> a response. See the `tools` parameter to see how to specify which tools <br> the model can call. <br>  |
|   ↳ `truncation` | string | No | `disabled` | `auto`, `disabled` | The truncation strategy to use for the model response. <br> - `auto`: If the context of this response and previous ones exceeds <br>   the model's context window size, the model will truncate the  <br>   response to fit the context window by dropping input items in the <br>   middle of the conversation.  <br> - `disabled` (default): If a model response will exceed the context window  <br>   size for a model, the request will fail with a 400 error. <br>  |
|   ↳ `id` | string | Yes |  |  | Unique identifier for this Response. <br>  |
|   ↳ `object` | string | Yes |  | `response` | The object type of this resource - always set to `response`. <br>  |
|   ↳ `status` | string | No |  | `completed`, `failed`, `in_progress`, `incomplete` | The status of the response generation. One of `completed`, `failed`,  <br> `in_progress`, or `incomplete`. <br>  |
|   ↳ `created_at` | number | Yes |  |  | Unix timestamp (in seconds) of when this Response was created. <br>  |
|   ↳ `error` | object (2 properties) | Yes |  |  | An error object returned when the model fails to generate a Response. <br>  |
|   ↳ `incomplete_details` | object (1 property) | Yes |  |  | Details about why the response is incomplete. <br>  |
|   ↳ `output` | array of anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | An array of content items generated by the model. <br>  <br> - The length and order of items in the `output` array is dependent <br>   on the model's response. <br> - Rather than accessing the first item in the `output` array and  <br>   assuming it's an `assistant` message with the content generated by <br>   the model, you might consider using the `output_text` property where <br>   supported in SDKs. <br>  |
|   ↳ `output_text` | string | No |  |  | SDK-only convenience property that contains the aggregated text output  <br> from all `output_text` items in the `output` array, if any are present.  <br> Supported in the Python and JavaScript SDKs. <br>  |
|   ↳ `usage` | object (5 properties) | No |  |  | Represents token usage details including input tokens, output tokens, <br> a breakdown of output tokens, and the total tokens used. <br>  |
|     ↳ `output_tokens` | integer | Yes |  |  | The number of output tokens. |
|     ↳ `output_tokens_details` | object (1 property) | Yes |  |  | A detailed breakdown of the output tokens. |
|     ↳ `total_tokens` | integer | Yes |  |  | The total number of tokens used. |
|   ↳ `parallel_tool_calls` | boolean | Yes | `true` |  | Whether to allow the model to run tool calls in parallel. <br>  |
**Example:**

```json
{
  "type": "response.incomplete",
  "response": {
    "id": "resp_123",
    "object": "response",
    "created_at": 1740855869,
    "status": "incomplete",
    "error": null, 
    "incomplete_details": {
      "reason": "max_tokens"
    },
    "instructions": null,
    "max_output_tokens": null,
    "model": "gpt-4o-mini-2024-07-18",
    "output": [],
    "previous_response_id": null,
    "reasoning_effort": null,
    "store": false,
    "temperature": 1,
    "text": {
      "format": {
        "type": "text"
      }
    },
    "tool_choice": "auto",
    "tools": [],
    "top_p": 1,
    "truncation": "disabled",
    "usage": null,
    "user": null,
    "metadata": {}
  }
}

```

##### Option 23:

**Type**: object (3 properties)

Emitted when a new output item is added.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_item.added` | The type of the event. Always `response.output_item.added`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that was added. <br>  |
| `item` | anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | The output item that was added. <br>  |
**Example:**

```json
{
  "type": "response.output_item.added",
  "output_index": 0,
  "item": {
    "id": "msg_123",
    "status": "in_progress",
    "type": "message",
    "role": "assistant",
    "content": []
  }
}

```

##### Option 24:

**Type**: object (3 properties)

Emitted when an output item is marked done.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_item.done` | The type of the event. Always `response.output_item.done`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that was marked done. <br>  |
| `item` | anyOf: object (5 properties) | object (5 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | The output item that was marked done. <br>  |
**Example:**

```json
{
  "type": "response.output_item.done",
  "output_index": 0,
  "item": {
    "id": "msg_123",
    "status": "completed",
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "In a shimmering forest under a sky full of stars, a lonely unicorn named Lila discovered a hidden pond that glowed with moonlight. Every night, she would leave sparkling, magical flowers by the water's edge, hoping to share her beauty with others. One enchanting evening, she woke to find a group of friendly animals gathered around, eager to be friends and share in her magic.",
        "annotations": []
      }
    ]
  }
}

```

##### Option 25:

**Type**: object (5 properties)

Emitted when a new reasoning summary part is added.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_part.added` | The type of the event. Always `response.reasoning_summary_part.added`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary part is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary part is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `part` | object (2 properties) | Yes |  |  | The summary part that was added. <br>  |
**Example:**

```json
{
  "type": "response.reasoning_summary_part.added",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "part": {
    "type": "summary_text",
    "text": ""
  }
}

```

##### Option 26:

**Type**: object (5 properties)

Emitted when a reasoning summary part is completed.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_part.done` | The type of the event. Always `response.reasoning_summary_part.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary part is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary part is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `part` | object (2 properties) | Yes |  |  | The completed summary part. <br>  |
**Example:**

```json
{
  "type": "response.reasoning_summary_part.done",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "part": {
    "type": "summary_text",
    "text": "**Responding to a greeting**\n\nThe user just said, \"Hello!\" So, it seems I need to engage. I'll greet them back and offer help since they're looking to chat. I could say something like, \"Hello! How can I assist you today?\" That feels friendly and open. They didn't ask a specific question, so this approach will work well for starting a conversation. Let's see where it goes from there!"
  }
}

```

##### Option 27:

**Type**: object (5 properties)

Emitted when a delta is added to a reasoning summary text.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_text.delta` | The type of the event. Always `response.reasoning_summary_text.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary text delta is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary text delta is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `delta` | string | Yes |  |  | The text delta that was added to the summary. <br>  |
**Example:**

```json
{
  "type": "response.reasoning_summary_text.delta",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "delta": "**Respond"
}

```

##### Option 28:

**Type**: object (5 properties)

Emitted when a reasoning summary text is completed.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.reasoning_summary_text.done` | The type of the event. Always `response.reasoning_summary_text.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the item this summary text is associated with. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item this summary text is associated with. <br>  |
| `summary_index` | integer | Yes |  |  | The index of the summary part within the reasoning summary. <br>  |
| `text` | string | Yes |  |  | The full text of the completed reasoning summary. <br>  |
**Example:**

```json
{
  "type": "response.reasoning_summary_text.done",
  "item_id": "rs_6806bfca0b2481918a5748308061a2600d3ce51bdffd5476",
  "output_index": 0,
  "summary_index": 0,
  "text": "**Responding to a greeting**\n\nThe user just said, \"Hello!\" So, it seems I need to engage. I'll greet them back and offer help since they're looking to chat. I could say something like, \"Hello! How can I assist you today?\" That feels friendly and open. They didn't ask a specific question, so this approach will work well for starting a conversation. Let's see where it goes from there!"
}

```

##### Option 29:

**Type**: object (5 properties)

Emitted when there is a partial refusal text.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.refusal.delta` | The type of the event. Always `response.refusal.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the refusal text is added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the refusal text is added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the refusal text is added to. <br>  |
| `delta` | string | Yes |  |  | The refusal text that is added. <br>  |
**Example:**

```json
{
  "type": "response.refusal.delta",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "delta": "refusal text so far"
}

```

##### Option 30:

**Type**: object (5 properties)

Emitted when refusal text is finalized.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.refusal.done` | The type of the event. Always `response.refusal.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the refusal text is finalized. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the refusal text is finalized. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the refusal text is finalized. <br>  |
| `refusal` | string | Yes |  |  | The refusal text that is finalized. <br>  |
**Example:**

```json
{
  "type": "response.refusal.done",
  "item_id": "item-abc",
  "output_index": 1,
  "content_index": 2,
  "refusal": "final refusal text"
}

```

##### Option 31:

**Type**: object (6 properties)

Emitted when a text annotation is added.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_text.annotation.added` | The type of the event. Always `response.output_text.annotation.added`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the text annotation was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the text annotation was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the text annotation was added to. <br>  |
| `annotation_index` | integer | Yes |  |  | The index of the annotation that was added. <br>  |
| `annotation` | oneOf: object (3 properties) | object (5 properties) | object (3 properties) | Yes |  |  |  |
**Example:**

```json
{
  "type": "response.output_text.annotation.added",
  "item_id": "msg_abc123",
  "output_index": 1,
  "content_index": 0,
  "annotation_index": 0,
  "annotation": {
    "type": "file_citation",
    "index": 390,
    "file_id": "file-4wDz5b167pAf72nx1h9eiN",
    "filename": "dragons.pdf"
  }
}

```

##### Option 32:

**Type**: object (5 properties)

Emitted when there is an additional text delta.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_text.delta` | The type of the event. Always `response.output_text.delta`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the text delta was added to. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the text delta was added to. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the text delta was added to. <br>  |
| `delta` | string | Yes |  |  | The text delta that was added. <br>  |
**Example:**

```json
{
  "type": "response.output_text.delta",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "delta": "In"
}

```

##### Option 33:

**Type**: object (5 properties)

Emitted when text content is finalized.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.output_text.done` | The type of the event. Always `response.output_text.done`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the output item that the text content is finalized. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the text content is finalized. <br>  |
| `content_index` | integer | Yes |  |  | The index of the content part that the text content is finalized. <br>  |
| `text` | string | Yes |  |  | The text content that is finalized. <br>  |
**Example:**

```json
{
  "type": "response.output_text.done",
  "item_id": "msg_123",
  "output_index": 0,
  "content_index": 0,
  "text": "In a shimmering forest under a sky full of stars, a lonely unicorn named Lila discovered a hidden pond that glowed with moonlight. Every night, she would leave sparkling, magical flowers by the water's edge, hoping to share her beauty with others. One enchanting evening, she woke to find a group of friendly animals gathered around, eager to be friends and share in her magic."
}

```

##### Option 34:

**Type**: object (3 properties)

Emitted when a web search call is completed.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.web_search_call.completed` | The type of the event. Always `response.web_search_call.completed`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the web search call is associated with. <br>  |
| `item_id` | string | Yes |  |  | Unique ID for the output item associated with the web search call. <br>  |
**Example:**

```json
{
  "type": "response.web_search_call.completed",
  "output_index": 0,
  "item_id": "ws_123",
}

```

##### Option 35:

**Type**: object (3 properties)

Emitted when a web search call is initiated.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.web_search_call.in_progress` | The type of the event. Always `response.web_search_call.in_progress`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the web search call is associated with. <br>  |
| `item_id` | string | Yes |  |  | Unique ID for the output item associated with the web search call. <br>  |
**Example:**

```json
{
  "type": "response.web_search_call.in_progress",
  "output_index": 0,
  "item_id": "ws_123",
}

```

##### Option 36:

**Type**: object (3 properties)

Emitted when a web search call is executing.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `response.web_search_call.searching` | The type of the event. Always `response.web_search_call.searching`. <br>  |
| `output_index` | integer | Yes |  |  | The index of the output item that the web search call is associated with. <br>  |
| `item_id` | string | Yes |  |  | Unique ID for the output item associated with the web search call. <br>  |
**Example:**

```json
{
  "type": "response.web_search_call.searching",
  "output_index": 0,
  "item_id": "ws_123",
}

```

## Examples

