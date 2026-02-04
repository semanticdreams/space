# ZAI Chat Completion

Create a chat completion model that generates AI replies for given conversation messages. It supports multimodal inputs (text, images, audio, video, file), offers configurable parameters (like temperature, max tokens, tool use), and supports both streaming and non-streaming output modes.

## Endpoint
- `POST /paas/v4/chat/completions`
- Base URL: `https://api.z.ai/api`

## Headers
- `Accept-Language` (enum<string>, default: en-US,en): Config desired response language for HTTP requests.
- `Authorization` (string): Use the following format for authentication: `Bearer <your api key>`
- `Content-Type`: `application/json`

## Example Request (cURL)
```
curl --request POST \
  --url https://api.z.ai/api/paas/v4/chat/completions \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json' \
  --data '
{
  "model": "glm-4.7",
  "messages": [
    {
      "role": "system",
      "content": "You are a useful AI assistant."
    },
    {
      "role": "user",
      "content": "Please tell us about the development of artificial intelligence."
    }
  ],
  "temperature": 1,
  "stream": false
}
'
```

## Request Body
### `do_sample` (boolean)
- Default: `true`
- When do_sample is true, sampling strategy is enabled; when do_sample is false, sampling strategy parameters such as temperature and top_p will not take effect. Default value is true .
- Example: `true`

### `max_tokens` (integer)
- Range: `1 <= x <= 131072`
- The maximum number of tokens for model output, the GLM-4.7 GLM-4.6 series supports 128K maximum output, the GLM-4.5 series supports 96K maximum output, the GLM-4.6v series supports 32K maximum output, the GLM-4.5v series supports 16K maximum output, GLM-4-32B-0414-128K supports 16K maximum output.
- Example: `1024`

### `messages` ((User Message · object | System Message · object | Assistant Message · object | Tool Message · object)[])
- The current conversation message list as the model’s prompt input, provided in JSON array format, e.g., {“role”: “user”, “content”: “Hello”} . Possible message types include system messages, user messages, assistant messages, and tool messages. Note: The input must not consist of system messages or assistant messages only.
- Fields:
  - `messages.content` (string)
    - Text message content
    - Example: `"What opportunities and challenges will the Chinese large model industry face in 2025?"`
  - `messages.role` (enum<string>)
    - Default: `user`
    - Role of the message author

### `model` (enum<string>)
- Default: `glm-4.7`
- The model code to be called. GLM-4.7 are the latest flagship model series, foundational models specifically designed for agent applications.
- Example: `"glm-4.7"`

### `request_id` (string)
- Passed by the user side, needs to be unique; used to distinguish each request. If not provided by the user side, the platform will generate one by default.

### `response_format` (object)
- Specifies the response format of the model. Defaults to text. Supports two formats:{ "type": "text" } plain text mode, returns natural language text, { "type": "json_object" } JSON mode, returns valid JSON data. When using JSON mode, it’s recommended to clearly request JSON output in the prompt.
- Fields:
  - `response_format.type` (enum<string>)
    - Default: `text`
    - Output format type: text for plain text, json_object for JSON-formatted output.

### `stop` (string[])
- Stop word list. Generation stops when the model encounters any specified string. Currently, only one stop word is supported, in the format ["stop_word1"].

### `stream` (boolean)
- Default: `false`
- This parameter should be set to false or omitted when using synchronous call. It indicates that the model returns all content at once after generating all content. Default value is false. If set to true, the model will return the generated content in chunks via standard Event Stream. When the Event Stream ends, a data: [DONE] message will be returned.
- Example: `false`

### `temperature` (number<float>)
- Default: `1`
- Range: `0 <= x <= 1`
- Sampling temperature, controls the randomness of the output, must be a positive number within the range: [0.0, 1.0] . The GLM-4.7 GLM-4.6 series default value is 1.0 , GLM-4.5 series default value is 0.6 , GLM-4-32B-0414-128K default value is 0.75 .
- Example: `1`

### `thinking` (object)
- Only supported by GLM-4.5 series and higher models. This parameter is used to control whether the model enable the chain of thought.
- Fields:
  - `thinking.clear_thinking` (boolean)
    - Default: `true`
    - Default value is True. Controls whether to clear reasoning_content from previous conversation turns. View more in Thinking Mode .
    - Example: `true`
  - `thinking.type` (enum<string>)
    - Default: `enabled`
    - Whether to enable the chain of thought(When enabled, GLM-4.7 GLM-4.5V will think compulsorily, while GLM-4.6, GLM-4.6V, GLM-4.5 and others will automatically determine whether to think), default: enabled

### `tool_choice` (enum<string>)
- Controls how the model selects a tool.

### `tool_stream` (boolean)
- Default: `false`
- Whether to enable streaming response for Function Calls. Default value is false. Only supported by GLM-4.6. Refer the Stream Tool Call
- Example: `false`

### `tools` ((Function Call · object | Retrieval · object | Web Search · object)[])
- A list of tools the model may call. Currently, only functions are supported as a tool. Use this to provide a list of functions the model may generate JSON inputs for. A max of 128 functions are supported.
- Fields:
  - `tools.function` (object)
  - `tools.function.description` (string)
    - A description of what the function does, used by the model to choose when and how to call the function.
  - `tools.function.name` (string)
    - The name of the function to be called. Must be a-z, A-Z, 0-9, or contain underscores and dashes, with a maximum length of 64.
  - `tools.function.parameters` (object)
    - Parameters defined using JSON Schema. Must pass a JSON Schema object to accurately define accepted parameters. Omit if no parameters are needed when calling the function.
  - `tools.type` (enum<string>)
    - Default: `function`

### `top_p` (number<float>)
- Default: `0.95`
- Range: `0.01 <= x <= 1`
- Another method of temperature sampling, value range is: [0.01, 1.0] . The GLM-4.7, GLM-4.6, GLM-4.5 series default value is 0.95 , GLM-4-32B-0414-128K default value is 0.9 .
- Example: `0.95`

### `user_id` (string)
- Unique ID for the end user, 6–128 characters. Avoid using sensitive information.

## Response
### `choices` (object[])
- List of model responses
- Fields:
  - `choices.finish_reason` (string)
    - Reason for model inference termination. Can be ‘stop’, ‘tool_calls’, ‘length’, ‘sensitive’, or ‘network_error’.
  - `choices.index` (integer)
    - Result index.
  - `choices.message` (object)
  - `choices.message.content` (string)
    - Current conversation content. Hits function is null, otherwise returns model inference result.
For the GLM-4.5V series models, the output may contain the reasoning process tags <think> </think> or the text boundary tags <|begin_of_box|> <|end_of_box|> .
  - `choices.message.reasoning_content` (string)
    - Reasoning content, supports by GLM-4.5 series.
  - `choices.message.role` (string)
    - Current conversation role, default is ‘assistant’ (model)
    - Example: `"assistant"`
  - `choices.message.tool_calls` (object[])
    - Function names and parameters generated by the model that should be called.
  - `choices.message.tool_calls.function` (object)
    - Contains the function name and JSON format parameters generated by the model.
  - `choices.message.tool_calls.function.arguments` (object)
    - JSON format of the function call parameters generated by the model. Validate the parameters before calling the function.
  - `choices.message.tool_calls.function.name` (string)
    - Model-generated function name.
  - `choices.message.tool_calls.id` (string)
    - Unique identifier for the hit function.
  - `choices.message.tool_calls.type` (string)
    - Tool type called by the model, currently only supports ‘function’.

### `created` (integer)
- Request creation time, Unix timestamp in seconds

### `id` (string)
- Task ID

### `model` (string)
- Model name

### `request_id` (string)
- Request ID

### `usage` (object)
- Token usage statistics returned when the model call ends.
- Fields:
  - `usage.completion_tokens` (number)
    - Number of output tokens
  - `usage.prompt_tokens` (number)
    - Number of tokens in user input
  - `usage.prompt_tokens_details` (object)
  - `usage.prompt_tokens_details.cached_tokens` (number)
    - Number of tokens served from cache
  - `usage.total_tokens` (integer)
    - Total number of tokens

### `web_search` (object[])
- Search results.
- Fields:
  - `web_search.content` (string)
    - Content summary.
  - `web_search.icon` (string)
    - Website icon.
  - `web_search.link` (string)
    - Result URL.
  - `web_search.media` (string)
    - Website name.
  - `web_search.publish_date` (string)
    - Website publication date.
  - `web_search.refer` (string)
    - Index number.
  - `web_search.title` (string)
    - Title.

## Example Response
```
{
  "id": "<string>",
  "request_id": "<string>",
  "created": 123,
  "model": "<string>",
  "choices": [
    {
      "index": 123,
      "message": {
        "role": "assistant",
        "content": "<string>",
        "reasoning_content": "<string>",
        "tool_calls": [
          {
            "function": {
              "name": "<string>",
              "arguments": {}
            },
            "id": "<string>",
            "type": "<string>"
          }
        ]
      },
      "finish_reason": "<string>"
    }
  ],
  "usage": {
    "prompt_tokens": 123,
    "completion_tokens": 123,
    "prompt_tokens_details": {
      "cached_tokens": 123
    },
    "total_tokens": 123
  },
  "web_search": [
    {
      "title": "<string>",
      "content": "<string>",
      "link": "<string>",
      "media": "<string>",
      "icon": "<string>",
      "refer": "<string>",
      "publish_date": "<string>"
    }
  ]
}
```
