# Create transcription session

`POST` `/realtime/transcription_sessions`

Create an ephemeral API token for use in client-side applications with the
Realtime API specifically for realtime transcriptions. 
Can be configured with the same session parameters as the `transcription_session.update` client event.

It responds with a session object, plus a `client_secret` key which contains
a usable ephemeral API token that can be used to authenticate browser clients
for the Realtime API.


## Request Body

Create an ephemeral API key with the given session configuration.

### Content Type: `application/json`

**Type**: object (6 properties)

Realtime transcription session object configuration.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `modalities` | unknown | No |  |  | The set of modalities the model can respond with. To disable audio, <br> set this to ["text"]. <br>  |
| `input_audio_format` | string | No | `pcm16` | `pcm16`, `g711_ulaw`, `g711_alaw` | The format of input audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br> For `pcm16`, input audio must be 16-bit PCM at a 24kHz sample rate,  <br> single channel (mono), and little-endian byte order. <br>  |
| `input_audio_transcription` | object (3 properties) | No |  |  | Configuration for input audio transcription. The client can optionally set the language and prompt for transcription, these offer additional guidance to the transcription service. <br>  |
|   ↳ `prompt` | string | No |  |  | An optional text to guide the model's style or continue a previous audio <br> segment. <br> For `whisper-1`, the [prompt is a list of keywords](/docs/guides/speech-to-text#prompting). <br> For `gpt-4o-transcribe` models, the prompt is a free text string, for example "expect words related to technology". <br>  |
| `turn_detection` | object (7 properties) | No |  |  | Configuration for turn detection, ether Server VAD or Semantic VAD. This can be set to `null` to turn off, in which case the client must manually trigger model response. <br> Server VAD means that the model will detect the start and end of speech based on audio volume and respond at the end of user speech. <br> Semantic VAD is more advanced and uses a turn detection model (in conjuction with VAD) to semantically estimate whether the user has finished speaking, then dynamically sets a timeout based on this probability. For example, if user audio trails off with "uhhm", the model will score a low probability of turn end and wait longer for the user to continue speaking. This can be useful for more natural conversations, but may have a higher latency. <br>  |
|   ↳ `threshold` | number | No |  |  | Used only for `server_vad` mode. Activation threshold for VAD (0.0 to 1.0), this defaults to 0.5. A  <br> higher threshold will require louder audio to activate the model, and  <br> thus might perform better in noisy environments. <br>  |
|   ↳ `prefix_padding_ms` | integer | No |  |  | Used only for `server_vad` mode. Amount of audio to include before the VAD detected speech (in  <br> milliseconds). Defaults to 300ms. <br>  |
|   ↳ `silence_duration_ms` | integer | No |  |  | Used only for `server_vad` mode. Duration of silence to detect speech stop (in milliseconds). Defaults  <br> to 500ms. With shorter values the model will respond more quickly,  <br> but may jump in on short pauses from the user. <br>  |
|   ↳ `create_response` | boolean | No | `true` |  | Whether or not to automatically generate a response when a VAD stop event occurs. Not available for transcription sessions. <br>  |
|   ↳ `interrupt_response` | boolean | No | `true` |  | Whether or not to automatically interrupt any ongoing response with output to the default <br> conversation (i.e. `conversation` of `auto`) when a VAD start event occurs. Not available for transcription sessions. <br>  |
| `input_audio_noise_reduction` | object (1 property) | No |  |  | Configuration for input audio noise reduction. This can be set to `null` to turn off. <br> Noise reduction filters audio added to the input audio buffer before it is sent to VAD and the model. <br> Filtering the audio can improve VAD and turn detection accuracy (reducing false positives) and model performance by improving perception of the input audio. <br>  |
| `include` | array of string | No |  |  | The set of items to include in the transcription. Current available items are: <br> - `item.input_audio_transcription.logprobs` <br>  |
## Responses

### 200 - Session created successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

A new Realtime transcription session configuration.

When a session is created on the server via REST API, the session object
also contains an ephemeral key. Default TTL for keys is one minute. This 
property is not present when a session is updated via the WebSocket API.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `client_secret` | object (2 properties) | Yes |  |  | Ephemeral key returned by the API. Only present when the session is <br> created on the server via REST API. <br>  |
| `modalities` | unknown | No |  |  | The set of modalities the model can respond with. To disable audio, <br> set this to ["text"]. <br>  |
| `input_audio_format` | string | No |  |  | The format of input audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br>  |
| `input_audio_transcription` | object (3 properties) | No |  |  | Configuration of the transcription model. <br>  |
|   ↳ `prompt` | string | No |  |  | An optional text to guide the model's style or continue a previous audio <br> segment. The [prompt](/docs/guides/speech-to-text#prompting) should match <br> the audio language. <br>  |
| `turn_detection` | object (4 properties) | No |  |  | Configuration for turn detection. Can be set to `null` to turn off. Server  <br> VAD means that the model will detect the start and end of speech based on  <br> audio volume and respond at the end of user speech. <br>  |
|   ↳ `prefix_padding_ms` | integer | No |  |  | Amount of audio to include before the VAD detected speech (in  <br> milliseconds). Defaults to 300ms. <br>  |
|   ↳ `silence_duration_ms` | integer | No |  |  | Duration of silence to detect speech stop (in milliseconds). Defaults  <br> to 500ms. With shorter values the model will respond more quickly,  <br> but may jump in on short pauses from the user. <br>  |
**Example:**

```json
{
  "id": "sess_BBwZc7cFV3XizEyKGDCGL",
  "object": "realtime.transcription_session",
  "expires_at": 1742188264,
  "modalities": ["audio", "text"],
  "turn_detection": {
    "type": "server_vad",
    "threshold": 0.5,
    "prefix_padding_ms": 300,
    "silence_duration_ms": 200
  },
  "input_audio_format": "pcm16",
  "input_audio_transcription": {
    "model": "gpt-4o-transcribe",
    "language": null,
    "prompt": ""
  },
  "client_secret": null
}

```

## Examples

### Request Examples

#### curl
```bash
curl -X POST https://api.openai.com/v1/realtime/transcription_sessions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'

```

### Response Example

```json
{
  "id": "sess_BBwZc7cFV3XizEyKGDCGL",
  "object": "realtime.transcription_session",
  "modalities": ["audio", "text"],
  "turn_detection": {
    "type": "server_vad",
    "threshold": 0.5,
    "prefix_padding_ms": 300,
    "silence_duration_ms": 200
  },
  "input_audio_format": "pcm16",
  "input_audio_transcription": {
    "model": "gpt-4o-transcribe",
    "language": null,
    "prompt": ""
  },
  "client_secret": null
}

```

