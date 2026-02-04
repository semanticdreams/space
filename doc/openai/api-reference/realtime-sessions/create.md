# Create session

`POST` `/realtime/sessions`

Create an ephemeral API token for use in client-side applications with the
Realtime API. Can be configured with the same session parameters as the
`session.update` client event.

It responds with a session object, plus a `client_secret` key which contains
a usable ephemeral API token that can be used to authenticate browser clients
for the Realtime API.


## Request Body

Create an ephemeral API key with the given session configuration.

### Content Type: `application/json`

**Type**: object (13 properties)

Realtime session object configuration.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `modalities` | unknown | No |  |  | The set of modalities the model can respond with. To disable audio, <br> set this to ["text"]. <br>  |
| `model` | string | No |  | `gpt-4o-realtime-preview`, `gpt-4o-realtime-preview-2024-10-01`, `gpt-4o-realtime-preview-2024-12-17`, `gpt-4o-mini-realtime-preview`, `gpt-4o-mini-realtime-preview-2024-12-17` | The Realtime model used for this session. <br>  |
| `instructions` | string | No |  |  | The default system instructions (i.e. system message) prepended to model  calls. This field allows the client to guide the model on desired  responses. The model can be instructed on response content and format,  (e.g. "be extremely succinct", "act friendly", "here are examples of good  responses") and on audio behavior (e.g. "talk quickly", "inject emotion  into your voice", "laugh frequently"). The instructions are not guaranteed  to be followed by the model, but they provide guidance to the model on the desired behavior. <br>  <br> Note that the server sets default instructions which will be used if this  field is not set and are visible in the `session.created` event at the  start of the session. <br>  |
| `voice` | anyOf: string | string | No |  |  | The voice the model uses to respond. Voice cannot be changed during the  <br> session once the model has responded with audio at least once. Current  <br> voice options are `alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, <br> `onyx`, `nova`, `sage`, `shimmer`, and `verse`. <br>  |
| `input_audio_format` | string | No | `pcm16` | `pcm16`, `g711_ulaw`, `g711_alaw` | The format of input audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br> For `pcm16`, input audio must be 16-bit PCM at a 24kHz sample rate,  <br> single channel (mono), and little-endian byte order. <br>  |
| `output_audio_format` | string | No | `pcm16` | `pcm16`, `g711_ulaw`, `g711_alaw` | The format of output audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br> For `pcm16`, output audio is sampled at a rate of 24kHz. <br>  |
| `input_audio_transcription` | object (3 properties) | No |  |  | Configuration for input audio transcription, defaults to off and can be  set to `null` to turn off once on. Input audio transcription is not native to the model, since the model consumes audio directly. Transcription runs  asynchronously through [the /audio/transcriptions endpoint](https://platform.openai.com/docs/api-reference/audio/createTranscription) and should be treated as guidance of input audio content rather than precisely what the model heard. The client can optionally set the language and prompt for transcription, these offer additional guidance to the transcription service. <br>  |
|   ↳ `prompt` | string | No |  |  | An optional text to guide the model's style or continue a previous audio <br> segment. <br> For `whisper-1`, the [prompt is a list of keywords](/docs/guides/speech-to-text#prompting). <br> For `gpt-4o-transcribe` models, the prompt is a free text string, for example "expect words related to technology". <br>  |
| `turn_detection` | object (7 properties) | No |  |  | Configuration for turn detection, ether Server VAD or Semantic VAD. This can be set to `null` to turn off, in which case the client must manually trigger model response. <br> Server VAD means that the model will detect the start and end of speech based on audio volume and respond at the end of user speech. <br> Semantic VAD is more advanced and uses a turn detection model (in conjuction with VAD) to semantically estimate whether the user has finished speaking, then dynamically sets a timeout based on this probability. For example, if user audio trails off with "uhhm", the model will score a low probability of turn end and wait longer for the user to continue speaking. This can be useful for more natural conversations, but may have a higher latency. <br>  |
|   ↳ `threshold` | number | No |  |  | Used only for `server_vad` mode. Activation threshold for VAD (0.0 to 1.0), this defaults to 0.5. A  <br> higher threshold will require louder audio to activate the model, and  <br> thus might perform better in noisy environments. <br>  |
|   ↳ `prefix_padding_ms` | integer | No |  |  | Used only for `server_vad` mode. Amount of audio to include before the VAD detected speech (in  <br> milliseconds). Defaults to 300ms. <br>  |
|   ↳ `silence_duration_ms` | integer | No |  |  | Used only for `server_vad` mode. Duration of silence to detect speech stop (in milliseconds). Defaults  <br> to 500ms. With shorter values the model will respond more quickly,  <br> but may jump in on short pauses from the user. <br>  |
|   ↳ `create_response` | boolean | No | `true` |  | Whether or not to automatically generate a response when a VAD stop event occurs. <br>  |
|   ↳ `interrupt_response` | boolean | No | `true` |  | Whether or not to automatically interrupt any ongoing response with output to the default <br> conversation (i.e. `conversation` of `auto`) when a VAD start event occurs. <br>  |
| `input_audio_noise_reduction` | object (1 property) | No |  |  | Configuration for input audio noise reduction. This can be set to `null` to turn off. <br> Noise reduction filters audio added to the input audio buffer before it is sent to VAD and the model. <br> Filtering the audio can improve VAD and turn detection accuracy (reducing false positives) and model performance by improving perception of the input audio. <br>  |
| `tools` | array of object (4 properties) | No |  |  | Tools (functions) available to the model. |
| `tool_choice` | string | No | `auto` |  | How the model chooses tools. Options are `auto`, `none`, `required`, or  <br> specify a function. <br>  |
| `temperature` | number | No | `0.8` |  | Sampling temperature for the model, limited to [0.6, 1.2]. For audio models a temperature of 0.8 is highly recommended for best performance. <br>  |
| `max_response_output_tokens` | oneOf: integer | string | No |  |  | Maximum number of output tokens for a single assistant response, <br> inclusive of tool calls. Provide an integer between 1 and 4096 to <br> limit output tokens, or `inf` for the maximum available tokens for a <br> given model. Defaults to `inf`. <br>  |


### Items in `tools` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | No |  | `function` | The type of the tool, i.e. `function`. |
| `name` | string | No |  |  | The name of the function. |
| `description` | string | No |  |  | The description of the function, including guidance on when and how  <br> to call it, and guidance about what to tell the user when calling  <br> (if anything). <br>  |
| `parameters` | object | No |  |  | Parameters of the function in JSON Schema. |
## Responses

### 200 - Session created successfully.

#### Content Type: `application/json`

**Type**: object (12 properties)

A new Realtime session configuration, with an ephermeral key. Default TTL
for keys is one minute.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `client_secret` | object (2 properties) | Yes |  |  | Ephemeral key returned by the API. |
| `modalities` | unknown | No |  |  | The set of modalities the model can respond with. To disable audio, <br> set this to ["text"]. <br>  |
| `instructions` | string | No |  |  | The default system instructions (i.e. system message) prepended to model  <br> calls. This field allows the client to guide the model on desired  <br> responses. The model can be instructed on response content and format,  <br> (e.g. "be extremely succinct", "act friendly", "here are examples of good  <br> responses") and on audio behavior (e.g. "talk quickly", "inject emotion  <br> into your voice", "laugh frequently"). The instructions are not guaranteed  <br> to be followed by the model, but they provide guidance to the model on the  <br> desired behavior. <br>  <br> Note that the server sets default instructions which will be used if this  <br> field is not set and are visible in the `session.created` event at the  <br> start of the session. <br>  |
| `voice` | anyOf: string | string | No |  |  | The voice the model uses to respond. Voice cannot be changed during the  <br> session once the model has responded with audio at least once. Current  <br> voice options are `alloy`, `ash`, `ballad`, `coral`, `echo` `sage`,  <br> `shimmer` and `verse`. <br>  |
| `input_audio_format` | string | No |  |  | The format of input audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br>  |
| `output_audio_format` | string | No |  |  | The format of output audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br>  |
| `input_audio_transcription` | object (1 property) | No |  |  | Configuration for input audio transcription, defaults to off and can be  <br> set to `null` to turn off once on. Input audio transcription is not native  <br> to the model, since the model consumes audio directly. Transcription runs  <br> asynchronously through Whisper and should be treated as rough guidance  <br> rather than the representation understood by the model. <br>  |
| `turn_detection` | object (4 properties) | No |  |  | Configuration for turn detection. Can be set to `null` to turn off. Server  <br> VAD means that the model will detect the start and end of speech based on  <br> audio volume and respond at the end of user speech. <br>  |
|   ↳ `prefix_padding_ms` | integer | No |  |  | Amount of audio to include before the VAD detected speech (in  <br> milliseconds). Defaults to 300ms. <br>  |
|   ↳ `silence_duration_ms` | integer | No |  |  | Duration of silence to detect speech stop (in milliseconds). Defaults  <br> to 500ms. With shorter values the model will respond more quickly,  <br> but may jump in on short pauses from the user. <br>  |
| `tools` | array of object (4 properties) | No |  |  | Tools (functions) available to the model. |
| `tool_choice` | string | No |  |  | How the model chooses tools. Options are `auto`, `none`, `required`, or  <br> specify a function. <br>  |
| `temperature` | number | No |  |  | Sampling temperature for the model, limited to [0.6, 1.2]. Defaults to 0.8. <br>  |
| `max_response_output_tokens` | oneOf: integer | string | No |  |  | Maximum number of output tokens for a single assistant response, <br> inclusive of tool calls. Provide an integer between 1 and 4096 to <br> limit output tokens, or `inf` for the maximum available tokens for a <br> given model. Defaults to `inf`. <br>  |


### Items in `tools` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | No |  | `function` | The type of the tool, i.e. `function`. |
| `name` | string | No |  |  | The name of the function. |
| `description` | string | No |  |  | The description of the function, including guidance on when and how  <br> to call it, and guidance about what to tell the user when calling  <br> (if anything). <br>  |
| `parameters` | object | No |  |  | Parameters of the function in JSON Schema. |
**Example:**

```json
{
  "id": "sess_001",
  "object": "realtime.session",
  "model": "gpt-4o-realtime-preview",
  "modalities": ["audio", "text"],
  "instructions": "You are a friendly assistant.",
  "voice": "alloy",
  "input_audio_format": "pcm16",
  "output_audio_format": "pcm16",
  "input_audio_transcription": {
      "model": "whisper-1"
  },
  "turn_detection": null,
  "tools": [],
  "tool_choice": "none",
  "temperature": 0.7,
  "max_response_output_tokens": 200,
  "client_secret": {
    "value": "ek_abc123", 
    "expires_at": 1234567890
  }
}

```

## Examples

### Request Examples

#### curl
```bash
curl -X POST https://api.openai.com/v1/realtime/sessions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-realtime-preview",
    "modalities": ["audio", "text"],
    "instructions": "You are a friendly assistant."
  }'

```

### Response Example

```json
{
  "id": "sess_001",
  "object": "realtime.session",
  "model": "gpt-4o-realtime-preview",
  "modalities": ["audio", "text"],
  "instructions": "You are a friendly assistant.",
  "voice": "alloy",
  "input_audio_format": "pcm16",
  "output_audio_format": "pcm16",
  "input_audio_transcription": {
      "model": "whisper-1"
  },
  "turn_detection": null,
  "tools": [],
  "tool_choice": "none",
  "temperature": 0.7,
  "max_response_output_tokens": 200,
  "client_secret": {
    "value": "ek_abc123", 
    "expires_at": 1234567890
  }
}

```

