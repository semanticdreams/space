# Create chat completion

`POST` `/chat/completions`

**Starting a new project?** We recommend trying [Responses](/docs/api-reference/responses) 
to take advantage of the latest OpenAI platform features. Compare
[Chat Completions with Responses](/docs/guides/responses-vs-chat-completions?api-mode=responses).

---

Creates a model response for the given chat conversation. Learn more in the
[text generation](/docs/guides/text-generation), [vision](/docs/guides/vision),
and [audio](/docs/guides/audio) guides.

Parameter support can differ depending on the model used to generate the
response, particularly for newer reasoning models. Parameters that are only
supported for reasoning models are noted below. For the current state of 
unsupported parameters in reasoning models, 
[refer to the reasoning guide](/docs/guides/reasoning).


## Request Body

### Content Type: `application/json`

**Type**: object (31 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `metadata` | map | No |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `temperature` | number | No | `1` |  | What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. <br> We generally recommend altering this or `top_p` but not both. <br>  |
| `top_p` | number | No | `1` |  | An alternative to sampling with temperature, called nucleus sampling, <br> where the model considers the results of the tokens with top_p probability <br> mass. So 0.1 means only the tokens comprising the top 10% probability mass <br> are considered. <br>  <br> We generally recommend altering this or `temperature` but not both. <br>  |
| `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
| `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
| `messages` | array of oneOf: object (3 properties) | object (3 properties) | object (3 properties) | object (7 properties) | object (3 properties) | object (3 properties) | Yes |  |  | A list of messages comprising the conversation so far. Depending on the <br> [model](/docs/models) you use, different message types (modalities) are <br> supported, like [text](/docs/guides/text-generation), <br> [images](/docs/guides/vision), and [audio](/docs/guides/audio). <br>  |
| `model` | anyOf: string | string | Yes |  |  | Model ID used to generate the response, like `gpt-4o` or `o3`. OpenAI <br> offers a wide range of models with different capabilities, performance <br> characteristics, and price points. Refer to the [model guide](/docs/models) <br> to browse and compare available models. <br>  |
| `modalities` | array of string | No |  |  | Output types that you would like the model to generate. <br> Most models are capable of generating text, which is the default: <br>  <br> `["text"]` <br>  <br> The `gpt-4o-audio-preview` model can also be used to  <br> [generate audio](/docs/guides/audio). To request that this model generate  <br> both text and audio responses, you can use: <br>  <br> `["text", "audio"]` <br>  |
| `reasoning_effort` | string | No | `medium` | `low`, `medium`, `high` | **o-series models only**  <br>  <br> Constrains effort on reasoning for  <br> [reasoning models](https://platform.openai.com/docs/guides/reasoning). <br> Currently supported values are `low`, `medium`, and `high`. Reducing <br> reasoning effort can result in faster responses and fewer tokens used <br> on reasoning in a response. <br>  |
| `max_completion_tokens` | integer | No |  |  | An upper bound for the number of tokens that can be generated for a completion, including visible output tokens and [reasoning tokens](/docs/guides/reasoning). <br>  |
| `frequency_penalty` | number | No | `0` |  | Number between -2.0 and 2.0. Positive values penalize new tokens based on <br> their existing frequency in the text so far, decreasing the model's <br> likelihood to repeat the same line verbatim. <br>  |
| `presence_penalty` | number | No | `0` |  | Number between -2.0 and 2.0. Positive values penalize new tokens based on <br> whether they appear in the text so far, increasing the model's likelihood <br> to talk about new topics. <br>  |
| `web_search_options` | object (2 properties) | No |  |  | This tool searches the web for relevant results to use in a response. <br> Learn more about the [web search tool](/docs/guides/tools-web-search?api-mode=chat). <br>  |
|       ↳ `timezone` | string | No |  |  | The [IANA timezone](https://timeapi.io/documentation/iana-timezones)  <br> of the user, e.g. `America/Los_Angeles`. <br>  |
|   ↳ `search_context_size` | string | No | `medium` | `low`, `medium`, `high` | High level guidance for the amount of context window space to use for the  <br> search. One of `low`, `medium`, or `high`. `medium` is the default. <br>  |
| `top_logprobs` | integer | No |  |  | An integer between 0 and 20 specifying the number of most likely tokens to <br> return at each token position, each with an associated log probability. <br> `logprobs` must be set to `true` if this parameter is used. <br>  |
| `response_format` | oneOf: object (1 property) | object (2 properties) | object (1 property) | No |  |  | An object specifying the format that the model must output. <br>  <br> Setting to `{ "type": "json_schema", "json_schema": {...} }` enables <br> Structured Outputs which ensures the model will match your supplied JSON <br> schema. Learn more in the [Structured Outputs <br> guide](/docs/guides/structured-outputs). <br>  <br> Setting to `{ "type": "json_object" }` enables the older JSON mode, which <br> ensures the message the model generates is valid JSON. Using `json_schema` <br> is preferred for models that support it. <br>  |
| `audio` | object (2 properties) | No |  |  | Parameters for audio output. Required when audio output is requested with <br> `modalities: ["audio"]`. [Learn more](/docs/guides/audio). <br>  |
| `store` | boolean | No | `false` |  | Whether or not to store the output of this chat completion request for  <br> use in our [model distillation](/docs/guides/distillation) or <br> [evals](/docs/guides/evals) products. <br>  |
| `stream` | boolean | No | `false` |  | If set to true, the model response data will be streamed to the client <br> as it is generated using [server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#Event_stream_format). <br> See the [Streaming section below](/docs/api-reference/chat/streaming) <br> for more information, along with the [streaming responses](/docs/guides/streaming-responses) <br> guide for more information on how to handle the streaming events. <br>  |
| `stop` | oneOf: string | array of string | No |  |  | Not supported with latest reasoning models `o3` and `o4-mini`. <br>  <br> Up to 4 sequences where the API will stop generating further tokens. The <br> returned text will not contain the stop sequence. <br>  |
| `logit_bias` | map | No |  |  | Modify the likelihood of specified tokens appearing in the completion. <br>  <br> Accepts a JSON object that maps tokens (specified by their token ID in the <br> tokenizer) to an associated bias value from -100 to 100. Mathematically, <br> the bias is added to the logits generated by the model prior to sampling. <br> The exact effect will vary per model, but values between -1 and 1 should <br> decrease or increase likelihood of selection; values like -100 or 100 <br> should result in a ban or exclusive selection of the relevant token. <br>  |
|   ↳ (additional properties) | integer | - | - | - | Additional properties of this object |
| `logprobs` | boolean | No | `false` |  | Whether to return log probabilities of the output tokens or not. If true, <br> returns the log probabilities of each output token returned in the <br> `content` of `message`. <br>  |
| `max_tokens` | integer | No |  |  | The maximum number of [tokens](/tokenizer) that can be generated in the <br> chat completion. This value can be used to control <br> [costs](https://openai.com/api/pricing/) for text generated via API. <br>  <br> This value is now deprecated in favor of `max_completion_tokens`, and is <br> not compatible with [o-series models](/docs/guides/reasoning). <br>  |
| `n` | integer | No | `1` |  | How many chat completion choices to generate for each input message. Note that you will be charged based on the number of generated tokens across all of the choices. Keep `n` as `1` to minimize costs. |
| `prediction` | oneOf: object (2 properties) | No |  |  | Configuration for a [Predicted Output](/docs/guides/predicted-outputs), <br> which can greatly improve response times when large parts of the model <br> response are known ahead of time. This is most common when you are <br> regenerating a file with only minor changes to most of the content. <br>  |
| `seed` | integer | No |  |  | This feature is in Beta. <br> If specified, our system will make a best effort to sample deterministically, such that repeated requests with the same `seed` and parameters should return the same result. <br> Determinism is not guaranteed, and you should refer to the `system_fingerprint` response parameter to monitor changes in the backend. <br>  |
| `stream_options` | object (1 property) | No |  |  | Options for streaming response. Only set this when you set `stream: true`. <br>  |
| `tools` | array of object (2 properties) | No |  |  | A list of tools the model may call. Currently, only functions are supported as a tool. Use this to provide a list of functions the model may generate JSON inputs for. A max of 128 functions are supported. <br>  |
| `tool_choice` | oneOf: string | object (2 properties) | No |  |  | Controls which (if any) tool is called by the model. <br> `none` means the model will not call any tool and instead generates a message. <br> `auto` means the model can pick between generating a message or calling one or more tools. <br> `required` means the model must call one or more tools. <br> Specifying a particular tool via `{"type": "function", "function": {"name": "my_function"}}` forces the model to call that tool. <br>  <br> `none` is the default when no tools are present. `auto` is the default if tools are present. <br>  |
| `parallel_tool_calls` | boolean | No | `true` |  | Whether to enable [parallel function calling](/docs/guides/function-calling#configuring-parallel-function-calling) during tool use. |
| `function_call` | oneOf: string | object (1 property) | No |  |  | Deprecated in favor of `tool_choice`. <br>  <br> Controls which (if any) function is called by the model. <br>  <br> `none` means the model will not call a function and instead generates a <br> message. <br>  <br> `auto` means the model can pick between generating a message or calling a <br> function. <br>  <br> Specifying a particular function via `{"name": "my_function"}` forces the <br> model to call that function. <br>  <br> `none` is the default when no functions are present. `auto` is the default <br> if functions are present. <br>  |
| `functions` | array of object (3 properties) | No |  |  | Deprecated in favor of `tools`. <br>  <br> A list of functions the model may generate JSON inputs for. <br>  |


### Items in `modalities` array

Each item is of type `string`. Allowed values: `text`, `audio`



### Items in `tools` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `function` | The type of the tool. Currently, only `function` is supported. |
| `function` | object (4 properties) | Yes |  |  |  |
|   ↳ `parameters` | object (map of object) | No |  |  | The parameters the functions accepts, described as a JSON Schema object. See the [guide](/docs/guides/function-calling) for examples, and the [JSON Schema reference](https://json-schema.org/understanding-json-schema/) for documentation about the format.  <br>  <br> Omitting `parameters` defines a function with an empty parameter list. |
|   ↳   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
|   ↳ `strict` | boolean | No | `false` |  | Whether to enable strict schema adherence when generating the function call. If set to true, the model will follow the exact schema defined in the `parameters` field. Only a subset of JSON Schema is supported when `strict` is `true`. Learn more about Structured Outputs in the [function calling guide](docs/guides/function-calling). |


### Items in `functions` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `description` | string | No |  |  | A description of what the function does, used by the model to choose when and how to call the function. |
| `name` | string | Yes |  |  | The name of the function to be called. Must be a-z, A-Z, 0-9, or contain underscores and dashes, with a maximum length of 64. |
| `parameters` | object (map of object) | No |  |  | The parameters the functions accepts, described as a JSON Schema object. See the [guide](/docs/guides/function-calling) for examples, and the [JSON Schema reference](https://json-schema.org/understanding-json-schema/) for documentation about the format.  <br>  <br> Omitting `parameters` defines a function with an empty parameter list. |
|   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (8 properties)

Represents a chat completion response returned by model, based on the provided input.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | A unique identifier for the chat completion. |
| `choices` | array of object (4 properties) | Yes |  |  | A list of chat completion choices. Can be more than one if `n` is greater than 1. |
| `created` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the chat completion was created. |
| `model` | string | Yes |  |  | The model used for the chat completion. |
| `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
| `system_fingerprint` | string | No |  |  | This fingerprint represents the backend configuration that the model runs with. <br>  <br> Can be used in conjunction with the `seed` request parameter to understand when backend changes have been made that might impact determinism. <br>  |
| `object` | string | Yes |  | `chat.completion` | The object type, which is always `chat.completion`. |
| `usage` | object (5 properties) | No |  |  | Usage statistics for the completion request. |
|   ↳ `total_tokens` | integer | Yes | `0` |  | Total number of tokens used in the request (prompt + completion). |
|   ↳ `completion_tokens_details` | object (4 properties) | No |  |  | Breakdown of tokens used in a completion. |
|     ↳ `reasoning_tokens` | integer | No | `0` |  | Tokens generated by the model for reasoning. |
|     ↳ `rejected_prediction_tokens` | integer | No | `0` |  | When using Predicted Outputs, the number of tokens in the <br> prediction that did not appear in the completion. However, like <br> reasoning tokens, these tokens are still counted in the total <br> completion tokens for purposes of billing, output, and context window <br> limits. <br>  |
|   ↳ `prompt_tokens_details` | object (2 properties) | No |  |  | Breakdown of tokens used in the prompt. |


### Items in `choices` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `finish_reason` | string | Yes |  | `stop`, `length`, `tool_calls`, `content_filter`, `function_call` | The reason the model stopped generating tokens. This will be `stop` if the model hit a natural stop point or a provided stop sequence, <br> `length` if the maximum number of tokens specified in the request was reached, <br> `content_filter` if content was omitted due to a flag from our content filters, <br> `tool_calls` if the model called a tool, or `function_call` (deprecated) if the model called a function. <br>  |
| `index` | integer | Yes |  |  | The index of the choice in the list of choices. |
| `message` | object (7 properties) | Yes |  |  | A chat completion message generated by the model. |
|   ↳ `tool_calls` | array of object (3 properties) | No |  |  | The tool calls generated by the model, such as function calls. |
|   ↳ `annotations` | array of object (2 properties) | No |  |  | Annotations for the message, when applicable, as when using the <br> [web search tool](/docs/guides/tools-web-search?api-mode=chat). <br>  |
|   ↳ `role` | string | Yes |  | `assistant` | The role of the author of this message. |
|   ↳ `function_call` | object (2 properties) | No |  |  | Deprecated and replaced by `tool_calls`. The name and arguments of a function that should be called, as generated by the model. |
|   ↳ `audio` | object (4 properties) | No |  |  | If the audio output modality is requested, this object contains data <br> about the audio response from the model. [Learn more](/docs/guides/audio). <br>  |
|     ↳ `data` | string | Yes |  |  | Base64 encoded audio bytes generated by the model, in the format <br> specified in the request. <br>  |
|     ↳ `transcript` | string | Yes |  |  | Transcript of the audio generated by the model. |


### Items in `tool_calls` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The ID of the tool call. |
| `type` | string | Yes |  | `function` | The type of the tool. Currently, only `function` is supported. |
| `function` | object (2 properties) | Yes |  |  | The function that the model called. |


### Items in `annotations` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `url_citation` | The type of the URL citation. Always `url_citation`. |
| `url_citation` | object (4 properties) | Yes |  |  | A URL citation when using web search. |
|   ↳ `url` | string | Yes |  |  | The URL of the web resource. |
|   ↳ `title` | string | Yes |  |  | The title of the web resource. |
| `logprobs` | object (2 properties) | Yes |  |  | Log probability information for the choice. |


### Items in `content` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |
| `top_logprobs` | array of object (3 properties) | Yes |  |  | List of the most likely tokens and their log probability, at this token position. In rare cases, there may be fewer than the number of requested `top_logprobs` returned. |


### Items in `top_logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |


### Items in `refusal` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |
| `top_logprobs` | array of object (3 properties) | Yes |  |  | List of the most likely tokens and their log probability, at this token position. In rare cases, there may be fewer than the number of requested `top_logprobs` returned. |


### Items in `top_logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |
**Example:**

```json
{
  "id": "chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG",
  "object": "chat.completion",
  "created": 1741570283,
  "model": "gpt-4o-2024-08-06",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The image shows a wooden boardwalk path running through a lush green field or meadow. The sky is bright blue with some scattered clouds, giving the scene a serene and peaceful atmosphere. Trees and shrubs are visible in the background.",
        "refusal": null,
        "annotations": []
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 1117,
    "completion_tokens": 46,
    "total_tokens": 1163,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": "fp_fc9f1d7035"
}

```

#### Content Type: `text/event-stream`

**Type**: object (8 properties)

Represents a streamed chunk of a chat completion response returned
by the model, based on the provided input. 
[Learn more](/docs/guides/streaming-responses).


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | A unique identifier for the chat completion. Each chunk has the same ID. |
| `choices` | array of object (4 properties) | Yes |  |  | A list of chat completion choices. Can contain more than one elements if `n` is greater than 1. Can also be empty for the <br> last chunk if you set `stream_options: {"include_usage": true}`. <br>  |
| `created` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the chat completion was created. Each chunk has the same timestamp. |
| `model` | string | Yes |  |  | The model to generate the completion. |
| `service_tier` | string | No | `auto` | `auto`, `default`, `flex` | Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service: <br>   - If set to 'auto', and the Project is Scale tier enabled, the system <br>     will utilize scale tier credits until they are exhausted. <br>   - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee. <br>   - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](/docs/guides/flex-processing). <br>   - When not set, the default behavior is 'auto'. <br>  <br>   When this parameter is set, the response body will include the `service_tier` utilized. <br>  |
| `system_fingerprint` | string | No |  |  | This fingerprint represents the backend configuration that the model runs with. <br> Can be used in conjunction with the `seed` request parameter to understand when backend changes have been made that might impact determinism. <br>  |
| `object` | string | Yes |  | `chat.completion.chunk` | The object type, which is always `chat.completion.chunk`. |
| `usage` | object (5 properties) | No |  |  | Usage statistics for the completion request. |
|   ↳ `total_tokens` | integer | Yes | `0` |  | Total number of tokens used in the request (prompt + completion). |
|   ↳ `completion_tokens_details` | object (4 properties) | No |  |  | Breakdown of tokens used in a completion. |
|     ↳ `reasoning_tokens` | integer | No | `0` |  | Tokens generated by the model for reasoning. |
|     ↳ `rejected_prediction_tokens` | integer | No | `0` |  | When using Predicted Outputs, the number of tokens in the <br> prediction that did not appear in the completion. However, like <br> reasoning tokens, these tokens are still counted in the total <br> completion tokens for purposes of billing, output, and context window <br> limits. <br>  |
|   ↳ `prompt_tokens_details` | object (2 properties) | No |  |  | Breakdown of tokens used in the prompt. |


### Items in `choices` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `delta` | object (5 properties) | Yes |  |  | A chat completion delta generated by streamed model responses. |
|   ↳ `tool_calls` | array of object (4 properties) | No |  |  |  |
|   ↳ `role` | string | No |  | `developer`, `system`, `user`, `assistant`, `tool` | The role of the author of this message. |
|   ↳ `refusal` | string | No |  |  | The refusal message generated by the model. |


### Items in `tool_calls` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `index` | integer | Yes |  |  |  |
| `id` | string | No |  |  | The ID of the tool call. |
| `type` | string | No |  | `function` | The type of the tool. Currently, only `function` is supported. |
| `function` | object (2 properties) | No |  |  |  |
| `logprobs` | object (2 properties) | No |  |  | Log probability information for the choice. |


### Items in `content` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |
| `top_logprobs` | array of object (3 properties) | Yes |  |  | List of the most likely tokens and their log probability, at this token position. In rare cases, there may be fewer than the number of requested `top_logprobs` returned. |


### Items in `top_logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |


### Items in `refusal` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |
| `top_logprobs` | array of object (3 properties) | Yes |  |  | List of the most likely tokens and their log probability, at this token position. In rare cases, there may be fewer than the number of requested `top_logprobs` returned. |


### Items in `top_logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token. |
| `logprob` | number | Yes |  |  | The log probability of this token, if it is within the top 20 most likely tokens. Otherwise, the value `-9999.0` is used to signify that the token is very unlikely. |
| `bytes` | array of integer | Yes |  |  | A list of integers representing the UTF-8 bytes representation of the token. Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token. |
| `finish_reason` | string | Yes |  | `stop`, `length`, `tool_calls`, `content_filter`, `function_call` | The reason the model stopped generating tokens. This will be `stop` if the model hit a natural stop point or a provided stop sequence, <br> `length` if the maximum number of tokens specified in the request was reached, <br> `content_filter` if content was omitted due to a flag from our content filters, <br> `tool_calls` if the model called a tool, or `function_call` (deprecated) if the model called a function. <br>  |
| `index` | integer | Yes |  |  | The index of the choice in the list of choices. |
**Example:**

```json
{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini", "system_fingerprint": "fp_44709d6fcb", "choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}

{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini", "system_fingerprint": "fp_44709d6fcb", "choices":[{"index":0,"delta":{"content":"Hello"},"logprobs":null,"finish_reason":null}]}

....

{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini", "system_fingerprint": "fp_44709d6fcb", "choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"stop"}]}

```

## Examples

