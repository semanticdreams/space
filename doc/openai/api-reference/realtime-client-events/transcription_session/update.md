# transcription_session.update

Send this event to update a transcription session.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `transcription_session.update` | The event type, must be `transcription_session.update`. |
| `session` | object (6 properties) | Yes |  |  | Realtime transcription session object configuration. |
|   ↳ `input_audio_transcription` | object (3 properties) | No |  |  | Configuration for input audio transcription. The client can optionally set the language and prompt for transcription, these offer additional guidance to the transcription service. <br>  |
|     ↳ `prompt` | string | No |  |  | An optional text to guide the model's style or continue a previous audio <br> segment. <br> For `whisper-1`, the [prompt is a list of keywords](/docs/guides/speech-to-text#prompting). <br> For `gpt-4o-transcribe` models, the prompt is a free text string, for example "expect words related to technology". <br>  |
|   ↳ `turn_detection` | object (7 properties) | No |  |  | Configuration for turn detection, ether Server VAD or Semantic VAD. This can be set to `null` to turn off, in which case the client must manually trigger model response. <br> Server VAD means that the model will detect the start and end of speech based on audio volume and respond at the end of user speech. <br> Semantic VAD is more advanced and uses a turn detection model (in conjuction with VAD) to semantically estimate whether the user has finished speaking, then dynamically sets a timeout based on this probability. For example, if user audio trails off with "uhhm", the model will score a low probability of turn end and wait longer for the user to continue speaking. This can be useful for more natural conversations, but may have a higher latency. <br>  |
|     ↳ `threshold` | number | No |  |  | Used only for `server_vad` mode. Activation threshold for VAD (0.0 to 1.0), this defaults to 0.5. A  <br> higher threshold will require louder audio to activate the model, and  <br> thus might perform better in noisy environments. <br>  |
|     ↳ `prefix_padding_ms` | integer | No |  |  | Used only for `server_vad` mode. Amount of audio to include before the VAD detected speech (in  <br> milliseconds). Defaults to 300ms. <br>  |
|     ↳ `silence_duration_ms` | integer | No |  |  | Used only for `server_vad` mode. Duration of silence to detect speech stop (in milliseconds). Defaults  <br> to 500ms. With shorter values the model will respond more quickly,  <br> but may jump in on short pauses from the user. <br>  |
|     ↳ `create_response` | boolean | No | `true` |  | Whether or not to automatically generate a response when a VAD stop event occurs. Not available for transcription sessions. <br>  |
|     ↳ `interrupt_response` | boolean | No | `true` |  | Whether or not to automatically interrupt any ongoing response with output to the default <br> conversation (i.e. `conversation` of `auto`) when a VAD start event occurs. Not available for transcription sessions. <br>  |
|   ↳ `input_audio_noise_reduction` | object (1 property) | No |  |  | Configuration for input audio noise reduction. This can be set to `null` to turn off. <br> Noise reduction filters audio added to the input audio buffer before it is sent to VAD and the model. <br> Filtering the audio can improve VAD and turn detection accuracy (reducing false positives) and model performance by improving perception of the input audio. <br>  |
|   ↳ `include` | array of string | No |  |  | The set of items to include in the transcription. Current available items are: <br> - `item.input_audio_transcription.logprobs` <br>  |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `transcription_session.update`.

**Type**: string

**Allowed values**: `transcription_session.update`

### `session` (required)

Realtime transcription session object configuration.

**Type**: object (6 properties)

**Nested Properties**:

* `modalities`, `input_audio_format`, `input_audio_transcription`, `turn_detection`, `input_audio_noise_reduction`, `include`

## Example

```json
{
  "type": "transcription_session.update",
  "session": {
    "input_audio_format": "pcm16",
    "input_audio_transcription": {
      "model": "gpt-4o-transcribe",
      "prompt": "",
      "language": ""
    },
    "turn_detection": {
      "type": "server_vad",
      "threshold": 0.5,
      "prefix_padding_ms": 300,
      "silence_duration_ms": 500,
      "create_response": true,
    },
    "input_audio_noise_reduction": {
      "type": "near_field"
    },
    "include": [
      "item.input_audio_transcription.logprobs",
    ]
  }
}

```

