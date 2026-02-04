# Create transcription

`POST` `/audio/transcriptions`

Transcribes audio into the input language.

## Request Body

### Content Type: `multipart/form-data`

**Type**: object (10 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `file` | file | Yes |  |  | The audio file object (not file name) to transcribe, in one of these formats: flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, or webm. <br>  |
| `model` | anyOf: string | string | Yes |  |  | ID of the model to use. The options are `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, and `whisper-1` (which is powered by our open source Whisper V2 model). <br>  |
| `language` | string | No |  |  | The language of the input audio. Supplying the input language in [ISO-639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) (e.g. `en`) format will improve accuracy and latency. <br>  |
| `prompt` | string | No |  |  | An optional text to guide the model's style or continue a previous audio segment. The [prompt](/docs/guides/speech-to-text#prompting) should match the audio language. <br>  |
| `response_format` | string | No | `json` | `json`, `text`, `srt`, `verbose_json`, `vtt` | The format of the output, in one of these options: `json`, `text`, `srt`, `verbose_json`, or `vtt`. For `gpt-4o-transcribe` and `gpt-4o-mini-transcribe`, the only supported format is `json`. <br>  |
| `temperature` | number | No | `0` |  | The sampling temperature, between 0 and 1. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. If set to 0, the model will use [log probability](https://en.wikipedia.org/wiki/Log_probability) to automatically increase the temperature until certain thresholds are hit. <br>  |
| `include[]` | array of string | No |  |  | Additional information to include in the transcription response.  <br> `logprobs` will return the log probabilities of the tokens in the  <br> response to understand the model's confidence in the transcription.  <br> `logprobs` only works with response_format set to `json` and only with  <br> the models `gpt-4o-transcribe` and `gpt-4o-mini-transcribe`. <br>  |
| `timestamp_granularities[]` | array of string | No | `["segment"]` |  | The timestamp granularities to populate for this transcription. `response_format` must be set `verbose_json` to use timestamp granularities. Either or both of these options are supported: `word`, or `segment`. Note: There is no additional latency for segment timestamps, but generating word timestamps incurs additional latency. <br>  |
| `stream` | boolean | No | `false` |  | If set to true, the model response data will be streamed to the client <br> as it is generated using [server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#Event_stream_format).  <br> See the [Streaming section of the Speech-to-Text guide](/docs/guides/speech-to-text?lang=curl#streaming-transcriptions) <br> for more information. <br>  <br> Note: Streaming is not supported for the `whisper-1` model and will be ignored. <br>  |
| `chunking_strategy` | anyOf: string | object (4 properties) | No |  |  | Controls how the audio is cut into chunks. When set to `"auto"`, the server first normalizes loudness and then uses voice activity detection (VAD) to choose boundaries. `server_vad` object can be provided to tweak VAD detection parameters manually. If unset, the audio is transcribed as a single block.  |


### Items in `include[]` array

Each item is of type `string`. Allowed values: `logprobs`. Default: `[]`



### Items in `timestamp_granularities[]` array

Each item is of type `string`. Allowed values: `word`, `segment`

## Responses

### 200 - OK

#### Content Type: `application/json`

**One of the following:**

##### Option 1:

**Type**: object (2 properties)

Represents a transcription response returned by model, based on the provided input.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `text` | string | Yes |  |  | The transcribed text. |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the tokens in the transcription. Only returned with the models `gpt-4o-transcribe` and `gpt-4o-mini-transcribe` if `logprobs` is added to the `include` array. <br>  |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | No |  |  | The token in the transcription. |
| `logprob` | number | No |  |  | The log probability of the token. |
| `bytes` | array of number | No |  |  | The bytes of the token. |
**Example:**

```json
{
  "text": "Imagine the wildest idea that you've ever had, and you're curious about how it might scale to something that's a 100, a 1,000 times bigger. This is a place where you can get to do that."
}

```

##### Option 2:

**Type**: object (5 properties)

Represents a verbose json transcription response returned by model, based on the provided input.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `language` | string | Yes |  |  | The language of the input audio. |
| `duration` | number | Yes |  |  | The duration of the input audio. |
| `text` | string | Yes |  |  | The transcribed text. |
| `words` | array of object (3 properties) | No |  |  | Extracted words and their corresponding timestamps. |
| `segments` | array of object (10 properties) | No |  |  | Segments of the transcribed text and their corresponding details. |


### Items in `words` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `word` | string | Yes |  |  | The text content of the word. |
| `start` | number | Yes |  |  | Start time of the word in seconds. |
| `end` | number | Yes |  |  | End time of the word in seconds. |


### Items in `segments` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | integer | Yes |  |  | Unique identifier of the segment. |
| `seek` | integer | Yes |  |  | Seek offset of the segment. |
| `start` | number | Yes |  |  | Start time of the segment in seconds. |
| `end` | number | Yes |  |  | End time of the segment in seconds. |
| `text` | string | Yes |  |  | Text content of the segment. |
| `tokens` | array of integer | Yes |  |  | Array of token IDs for the text content. |
| `temperature` | number | Yes |  |  | Temperature parameter used for generating the segment. |
| `avg_logprob` | number | Yes |  |  | Average logprob of the segment. If the value is lower than -1, consider the logprobs failed. |
| `compression_ratio` | number | Yes |  |  | Compression ratio of the segment. If the value is greater than 2.4, consider the compression failed. |
| `no_speech_prob` | number | Yes |  |  | Probability of no speech in the segment. If the value is higher than 1.0 and the `avg_logprob` is below -1, consider this segment silent. |
**Example:**

```json
{
  "task": "transcribe",
  "language": "english",
  "duration": 8.470000267028809,
  "text": "The beach was a popular spot on a hot summer day. People were swimming in the ocean, building sandcastles, and playing beach volleyball.",
  "segments": [
    {
      "id": 0,
      "seek": 0,
      "start": 0.0,
      "end": 3.319999933242798,
      "text": " The beach was a popular spot on a hot summer day.",
      "tokens": [
        50364, 440, 7534, 390, 257, 3743, 4008, 322, 257, 2368, 4266, 786, 13, 50530
      ],
      "temperature": 0.0,
      "avg_logprob": -0.2860786020755768,
      "compression_ratio": 1.2363636493682861,
      "no_speech_prob": 0.00985979475080967
    },
    ...
  ]
}

```

#### Content Type: `text/event-stream`

**Any of the following:**

##### Option 1:

**Type**: object (3 properties)

Emitted when there is an additional text delta. This is also the first event emitted when the transcription starts. Only emitted when you [create a transcription](/docs/api-reference/audio/create-transcription) with the `Stream` parameter set to `true`.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `transcript.text.delta` | The type of the event. Always `transcript.text.delta`. <br>  |
| `delta` | string | Yes |  |  | The text delta that was additionally transcribed. <br>  |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the delta. Only included if you [create a transcription](/docs/api-reference/audio/create-transcription) with the `include[]` parameter set to `logprobs`. <br>  |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | No |  |  | The token that was used to generate the log probability. <br>  |
| `logprob` | number | No |  |  | The log probability of the token. <br>  |
| `bytes` | array | No |  |  | The bytes that were used to generate the log probability. <br>  |
**Example:**

```json
{
  "type": "transcript.text.delta",
  "delta": " wonderful"
}

```

##### Option 2:

**Type**: object (3 properties)

Emitted when the transcription is complete. Contains the complete transcription text. Only emitted when you [create a transcription](/docs/api-reference/audio/create-transcription) with the `Stream` parameter set to `true`.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `transcript.text.done` | The type of the event. Always `transcript.text.done`. <br>  |
| `text` | string | Yes |  |  | The text that was transcribed. <br>  |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the individual tokens in the transcription. Only included if you [create a transcription](/docs/api-reference/audio/create-transcription) with the `include[]` parameter set to `logprobs`. <br>  |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | No |  |  | The token that was used to generate the log probability. <br>  |
| `logprob` | number | No |  |  | The log probability of the token. <br>  |
| `bytes` | array | No |  |  | The bytes that were used to generate the log probability. <br>  |
**Example:**

```json
{
  "type": "transcript.text.done",
  "text": "I see skies of blue and clouds of white, the bright blessed days, the dark sacred nights, and I think to myself, what a wonderful world."
}

```

## Examples

