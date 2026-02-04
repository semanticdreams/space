# transcription_session.updated

Returned when a transcription session is updated with a `transcription_session.update` event, unless 
there is an error.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `transcription_session.updated` | The event type, must be `transcription_session.updated`. |
| `session` | object (5 properties) | Yes |  |  | A new Realtime transcription session configuration. <br>  <br> When a session is created on the server via REST API, the session object <br> also contains an ephemeral key. Default TTL for keys is one minute. This  <br> property is not present when a session is updated via the WebSocket API. <br>  |
|   ↳ `input_audio_format` | string | No |  |  | The format of input audio. Options are `pcm16`, `g711_ulaw`, or `g711_alaw`. <br>  |
|   ↳ `input_audio_transcription` | object (3 properties) | No |  |  | Configuration of the transcription model. <br>  |
|     ↳ `prompt` | string | No |  |  | An optional text to guide the model's style or continue a previous audio <br> segment. The [prompt](/docs/guides/speech-to-text#prompting) should match <br> the audio language. <br>  |
|   ↳ `turn_detection` | object (4 properties) | No |  |  | Configuration for turn detection. Can be set to `null` to turn off. Server  <br> VAD means that the model will detect the start and end of speech based on  <br> audio volume and respond at the end of user speech. <br>  |
|     ↳ `prefix_padding_ms` | integer | No |  |  | Amount of audio to include before the VAD detected speech (in  <br> milliseconds). Defaults to 300ms. <br>  |
|     ↳ `silence_duration_ms` | integer | No |  |  | Duration of silence to detect speech stop (in milliseconds). Defaults  <br> to 500ms. With shorter values the model will respond more quickly,  <br> but may jump in on short pauses from the user. <br>  |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `transcription_session.updated`.

**Type**: string

**Allowed values**: `transcription_session.updated`

### `session` (required)

A new Realtime transcription session configuration.

When a session is created on the server via REST API, the session object
also contains an ephemeral key. Default TTL for keys is one minute. This 
property is not present when a session is updated via the WebSocket API.


**Type**: object (5 properties)

**Nested Properties**:

* `client_secret`, `modalities`, `input_audio_format`, `input_audio_transcription`, `turn_detection`

## Example

```json
{
  "event_id": "event_5678",
  "type": "transcription_session.updated",
  "session": {
    "id": "sess_001",
    "object": "realtime.transcription_session",
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
      // "interrupt_response": false  -- this will NOT be returned
    },
    "input_audio_noise_reduction": {
      "type": "near_field"
    },
    "include": [
      "item.input_audio_transcription.avg_logprob",
    ],
  }
}

```

